import Foundation
import MLX
import MLXNN
import MLXFast

/// Faithful Swift/MLX port of laya_mlx/model.py (ModernBERT-large encoder +
/// Laya decision head), inference only.
///
/// Deviations are none by intent: the op sequence, dtypes, mask semantics
/// (boolean keep-masks straight into SDPA, padded queries may see valid keys),
/// the layer-0 identity attention norm, the gated MLP (gelu on the value
/// chunk), the pre-norm decision head with ReLU feed-forward, and the float32
/// cast at the scorer output all mirror the validated Python implementation.

struct Linear {
    let weight: MLXArray  // [out, in]
    let bias: MLXArray?

    func apply(_ x: MLXArray) -> MLXArray {
        let wT = weight.transposed()
        if let bias {
            return matmul(x, wT) + bias
        }
        return matmul(x, wT)
    }
}

struct LayerNormBlock {
    let weight: MLXArray
    let bias: MLXArray?
    let eps: Float

    func apply(_ x: MLXArray) -> MLXArray {
        // Mean/variance accumulate in float32 (mlx's own fast LayerNorm
        // does the same): in float16 the squared deviations overflow to
        // inf at the deep layers' magnitudes and the output collapses to 0.
        let xf = x.asType(.float32)
        let mu = xf.mean(axis: -1, keepDims: true)
        let centered = xf - mu
        let v = (centered * centered).mean(axis: -1, keepDims: true)
        let normed = centered / sqrt(v + eps)
        if let bias {
            return (normed * weight.asType(.float32) + bias.asType(.float32))
                .asType(x.dtype)
        }
        return (normed * weight.asType(.float32)).asType(x.dtype)
    }
}

struct EncoderAttention {
    let wqkv: Linear
    let wo: Linear
    let ropeBase: Float
    let numHeads: Int
    let headDim: Int

    func apply(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let b = x.dim(0), length = x.dim(1)
        let qkv = wqkv.apply(x).reshaped([b, length, 3, numHeads, headDim])
        let q = qkv.take(.init(0), axis: 2).transposed(0, 2, 1, 3)
        let k = qkv.take(.init(1), axis: 2).transposed(0, 2, 1, 3)
        let v = qkv.take(.init(2), axis: 2).transposed(0, 2, 1, 3)
        let qr = MLXFast.RoPE(
            q, dimensions: headDim, traditional: false, base: ropeBase, scale: 1.0, offset: 0)
        let kr = MLXFast.RoPE(
            k, dimensions: headDim, traditional: false, base: ropeBase, scale: 1.0, offset: 0)
        let out = scaledDotProductAttention(
            queries: qr, keys: kr, values: v,
            scale: Float(pow(Double(headDim), -0.5)), mask: mask)
        return wo.apply(out.transposed(0, 2, 1, 3).reshaped([b, length, numHeads * headDim]))
    }
}

struct EncoderMLP {
    let wi: Linear
    let wo: Linear

    func apply(_ x: MLXArray) -> MLXArray {
        let parts = split(wi.apply(x), parts: 2, axis: -1)
        let value = parts[0]
        let gate = parts[1]
        return wo.apply(MLXNN.gelu(value) * gate)
    }
}

struct EncoderLayer {
    let attentionType: String
    let attnNorm: LayerNormBlock?  // nil at layer 0 (identity)
    let attn: EncoderAttention
    let mlpNorm: LayerNormBlock
    let mlp: EncoderMLP

    func apply(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let normed = attnNorm != nil ? attnNorm!.apply(x) : x
        let h = x + attn.apply(normed, mask: mask)
        return h + mlp.apply(mlpNorm.apply(h))
    }
}

struct ModernBert {
    let tokEmbeddings: MLXArray  // [vocab, hidden]
    let embeddingsNorm: LayerNormBlock
    let layers: [EncoderLayer]
    let finalNorm: LayerNormBlock
    let localAttention: Int

    func apply(_ inputIds: MLXArray, attentionMask: MLXArray) -> MLXArray {
        var x = embeddingsNorm.apply(tokEmbeddings.take(inputIds, axis: 0))
        let masks = AttentionMasks.build(attentionMask: attentionMask, window: localAttention)
        for layer in layers {
            x = layer.apply(x, mask: masks[layer.attentionType]!)
        }
        return finalNorm.apply(x)
    }
}

enum AttentionMasks {
    /// Boolean key masks mirroring laya_mlx.model.attention_masks:
    /// full = key validity; local additionally bounds |i-j| <= window/2,
    /// and padded query rows may see valid keys (they are never used as
    /// keys or pooled, so valid-token results are unchanged).
    static func build(attentionMask: MLXArray, window: Int) -> [String: MLXArray] {
        let valid = attentionMask.asType(.bool)
        let full = valid[0..., .newAxis, .newAxis, 0...]
        let length = valid.dim(1)
        let positions = MLXArray(Int32(0)..<Int32(length))
        let distance = abs(positions[0..., .newAxis] - positions[.newAxis, 0...])
        var local = distance .<= MLXArray(Int32(window / 2))
        // (local | ~validQuery) & full — python:
        // local = (local[None,None] | ~valid[:,None,:,None]) & full
        let rowValid = valid[0..., .newAxis, 0..., .newAxis]  // [B,1,L,1]
        local = (local[.newAxis, .newAxis, 0..., 0...] | .!rowValid) & full
        return ["full_attention": full, "sliding_attention": local]
    }
}

struct HeadAttention {
    let inProj: Linear
    let outProj: Linear
    let numHeads: Int
    let headDim: Int

    func apply(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let b = x.dim(0), length = x.dim(1)
        let qkv = inProj.apply(x).reshaped([b, length, 3, numHeads, headDim])
        let q = qkv.take(.init(0), axis: 2).transposed(0, 2, 1, 3)
        let k = qkv.take(.init(1), axis: 2).transposed(0, 2, 1, 3)
        let v = qkv.take(.init(2), axis: 2).transposed(0, 2, 1, 3)
        let out = scaledDotProductAttention(
            queries: q, keys: k, values: v,
            scale: Float(pow(Double(headDim), -0.5)), mask: mask)
        return outProj.apply(out.transposed(0, 2, 1, 3).reshaped([b, length, numHeads * headDim]))
    }
}

struct HeadLayer {
    let selfAttn: HeadAttention
    let norm1: LayerNormBlock
    let norm2: LayerNormBlock
    let linear1: Linear
    let linear2: Linear

    func apply(_ x: MLXArray, mask: MLXArray) -> MLXArray {
        let h = x + selfAttn.apply(norm1.apply(x), mask: mask)
        // PyTorch TransformerEncoderLayer defaults to ReLU, even though the
        // encoder and the scoring head use GELU.
        return h + linear2.apply(MLXNN.relu(linear1.apply(norm2.apply(h))))
    }
}

struct LayaWeights {
    var encoder: ModernBert!
    var headLayers: [HeadLayer] = []
    var typeEmb: MLXArray!  // [3, hidden]
    var scorerNorm: LayerNormBlock!
    var scorerLinear1: Linear!
    var scorerLinear2: Linear!
    var actLinear1: Linear!  // [256, hidden + 4]
    var actLinear2: Linear!  // [2, 256]

    let headDim: Int
    let numHeads: Int
    let hiddenSize: Int
    let normEps: Float

    /// Builds the full model from a safetensors weight map keyed by the
    /// checkpoint's MLX-style names.
    static func load(modelDir: String) throws -> LayaWeights {
        let encoderConfigURL = URL(fileURLWithPath: modelDir).appendingPathComponent(
            "encoder/config.json")
        let encoderConfigData = try Data(contentsOf: encoderConfigURL)
        guard
            let cfg = try JSONSerialization.jsonObject(with: encoderConfigData) as? [String: Any]
        else {
            throw NSError(
                domain: "laya.native", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "unreadable encoder/config.json"])
        }
        let hiddenSize = cfg["hidden_size"] as! Int
        let intermediateSize = cfg["intermediate_size"] as! Int
        let numLayers = cfg["num_hidden_layers"] as! Int
        let numHeads = cfg["num_attention_heads"] as! Int
        let layerTypes = cfg["layer_types"] as! [String]
        let localAttention = cfg["local_attention"] as! Int
        let normEps = Float(cfg["layer_norm_eps"] as? Double ?? 1e-5)
        let headDim = hiddenSize / numHeads
        let ropeParameters = cfg["rope_parameters"] as? [String: Any] ?? [:]

        func ropeBase(_ kind: String) -> Float {
            if let params = ropeParameters[kind] as? [String: Any],
                let theta = params["rope_theta"] as? Double
            {
                return Float(theta)
            }
            return kind == "full_attention" ? 160_000.0 : 10_000.0
        }

        // names
        var wanted = Set<String>()
        func enc(_ n: String) { wanted.insert("encoder.\(n)") }
        enc("embeddings.tok_embeddings.weight")
        enc("embeddings.norm.weight")
        enc("final_norm.weight")
        for i in 0..<numLayers {
            enc("layers.\(i).attn.Wqkv.weight")
            enc("layers.\(i).attn.Wo.weight")
            enc("layers.\(i).attn_norm.weight")
            enc("layers.\(i).mlp.Wi.weight")
            enc("layers.\(i).mlp.Wo.weight")
            enc("layers.\(i).mlp_norm.weight")
        }
        let agentConfigURL = URL(fileURLWithPath: modelDir).appendingPathComponent(
            "rl_agent_config.json")
        let agentConfigData = try Data(contentsOf: agentConfigURL)
        guard
            let agentCfg = try JSONSerialization.jsonObject(with: agentConfigData)
                as? [String: Any]
        else {
            throw NSError(
                domain: "laya.native", code: 11,
                userInfo: [NSLocalizedDescriptionKey: "unreadable rl_agent_config.json"])
        }
        let headCount = agentCfg["head_layers"] as? Int ?? 2
        for i in 0..<headCount {
            for suffix in [
                "self_attn.in_proj.weight", "self_attn.in_proj.bias",
                "self_attn.out_proj.weight", "self_attn.out_proj.bias",
                "norm1.weight", "norm1.bias", "norm2.weight", "norm2.bias",
                "linear1.weight", "linear1.bias", "linear2.weight", "linear2.bias",
            ] {
                wanted.insert("head.layers.\(i).\(suffix)")
            }
        }
        for suffix in [
            "type_emb.weight", "temperature",
            "scorer.layers.0.weight", "scorer.layers.0.bias",
            "scorer.layers.1.weight", "scorer.layers.1.bias",
            "scorer.layers.3.weight", "scorer.layers.3.bias",
            "act_head.layers.0.weight", "act_head.layers.0.bias",
            "act_head.layers.2.weight", "act_head.layers.2.bias",
        ] {
            wanted.insert(suffix)
        }

        let weights = try Safetensors.loadFloat16(
            path: URL(fileURLWithPath: modelDir).appendingPathComponent("model.safetensors").path,
            wanted: wanted)

        func take(_ name: String) throws -> MLXArray {
            guard let w = weights[name] else {
                throw NSError(
                    domain: "laya.native", code: 12,
                    userInfo: [NSLocalizedDescriptionKey: "missing checkpoint tensor \(name)"])
            }
            return w
        }
        func linear(_ name: String, biasName: String?) throws -> Linear {
            Linear(
                weight: try take(name),
                bias: biasName == nil ? nil : try take(biasName!))
        }
        func norm(_ name: String, biasName: String?) throws -> LayerNormBlock {
            LayerNormBlock(
                weight: try take(name),
                bias: biasName == nil ? nil : try take(biasName!), eps: normEps)
        }

        var layers: [EncoderLayer] = []
        for i in 0..<numLayers {
            layers.append(
                EncoderLayer(
                    attentionType: layerTypes[i],
                    attnNorm: try (i == 0
                        ? nil
                        : norm(
                            "encoder.layers.\(i).attn_norm.weight",
                            biasName: nil)),
                    attn: EncoderAttention(
                        wqkv: try linear(
                            "encoder.layers.\(i).attn.Wqkv.weight", biasName: nil),
                        wo: try linear("encoder.layers.\(i).attn.Wo.weight", biasName: nil),
                        ropeBase: ropeBase(layerTypes[i]),
                        numHeads: numHeads,
                        headDim: headDim),
                    mlpNorm: try norm("encoder.layers.\(i).mlp_norm.weight", biasName: nil),
                    mlp: EncoderMLP(
                        wi: Linear(
                            weight: try take("encoder.layers.\(i).mlp.Wi.weight"), bias: nil),
                        wo: Linear(
                            weight: try take("encoder.layers.\(i).mlp.Wo.weight"), bias: nil))
                ))
        }

        var head: [HeadLayer] = []
        for i in 0..<headCount {
            head.append(
                HeadLayer(
                    selfAttn: HeadAttention(
                        inProj: try linear(
                            "head.layers.\(i).self_attn.in_proj.weight",
                            biasName: "head.layers.\(i).self_attn.in_proj.bias"),
                        outProj: try linear(
                            "head.layers.\(i).self_attn.out_proj.weight",
                            biasName: "head.layers.\(i).self_attn.out_proj.bias"),
                        numHeads: max(1, hiddenSize / 64),
                        headDim: hiddenSize / max(1, hiddenSize / 64)),
                    norm1: try norm(
                        "head.layers.\(i).norm1.weight", biasName: "head.layers.\(i).norm1.bias"),
                    norm2: try norm(
                        "head.layers.\(i).norm2.weight", biasName: "head.layers.\(i).norm2.bias"),
                    linear1: try linear(
                        "head.layers.\(i).linear1.weight",
                        biasName: "head.layers.\(i).linear1.bias"),
                    linear2: try linear(
                        "head.layers.\(i).linear2.weight",
                        biasName: "head.layers.\(i).linear2.bias")))
        }

        let model = LayaWeights(
            encoder: ModernBert(
                tokEmbeddings: try take("encoder.embeddings.tok_embeddings.weight"),
                embeddingsNorm: try norm("encoder.embeddings.norm.weight", biasName: nil),
                layers: layers,
                finalNorm: try norm("encoder.final_norm.weight", biasName: nil),
                localAttention: localAttention),
            headLayers: head,
            typeEmb: try take("type_emb.weight"),
            scorerNorm: try norm("scorer.layers.0.weight", biasName: "scorer.layers.0.bias"),
            scorerLinear1: try linear(
                "scorer.layers.1.weight", biasName: "scorer.layers.1.bias"),
            scorerLinear2: try linear(
                "scorer.layers.3.weight", biasName: "scorer.layers.3.bias"),
            actLinear1: try linear(
                "act_head.layers.0.weight", biasName: "act_head.layers.0.bias"),
            actLinear2: try linear(
                "act_head.layers.2.weight", biasName: "act_head.layers.2.bias"),
            headDim: headDim,
            numHeads: numHeads,
            hiddenSize: hiddenSize,
            normEps: normEps)
        return model
    }

    struct Batch {
        /// [B][L] token ids (padded by the caller).
        var inputIds: MLXArray
        /// [B][L] 1 = real token, 0 = pad.
        var attentionMask: MLXArray
        /// [B][Kmax] marker positions.
        var markerPos: MLXArray
        /// [B][Kmax] 1 = real marker.
        var markerMask: MLXArray
        /// [B] question type index (0 choice, 1 score, 2 noul).
        var qtype: MLXArray
    }

    /// Returns (logits [B][Kmax] float32, action logits [B][2] float32).
    func forward(_ batch: Batch) -> (MLXArray, MLXArray) {
        var h = encoder.apply(batch.inputIds, attentionMask: batch.attentionMask)
        h = h + typeEmb.take(batch.qtype, axis: 0)[0..., .newAxis, 0...]
        let headMask = batch.attentionMask[0..., .newAxis, .newAxis, 0...].asType(.bool)
        for layer in headLayers {
            h = layer.apply(h, mask: headMask)
        }
        let b = h.dim(0)
        let kmax = batch.markerMask.dim(1)
        let lengths = h.dim(1)
        // Gather marker vectors: flat take along axis 0 of [B*L, hidden].
        let flat = h.reshaped([b * lengths, hiddenSize])
        let rows = MLXArray(Int32(0)..<Int32(b)) * MLXArray(Int32(lengths))
        let flatIndex = maximum(batch.markerPos, MLXArray(Int32(0))) + rows[0..., .newAxis]
        let markers = flat.take(flatIndex.reshaped([b * kmax]), axis: 0).reshaped([
            b, kmax, hiddenSize,
        ])

        var logits = scorerLinear2.apply(
            MLXNN.gelu(scorerLinear1.apply(scorerNorm.apply(markers)))
        ).reshaped([b, kmax]).asType(.float32)
        logits = which(batch.markerMask.asType(.bool), logits, MLXArray(Float32(-1e4)))

        // Action head sees the pooled sequence plus a detached summary of the
        // answer distribution (the checkpoint's J1-M "escalate" feature set).
        let p = softmax(logits, axis: -1)
        let counts = maximum(batch.markerMask.asType(.float32).sum(axis: -1), MLXArray(Float32(2)))
        let entropy = -((p * log(maximum(p, MLXArray(Float32(1e-9))))).sum(axis: -1))
            / log(counts)
        let sortedP = sorted(p, axis: -1)
        let top1 = sortedP.take(.init(kmax - 1), axis: 1)
        let top2 = sortedP.take(.init(kmax - 2), axis: 1)
        let features = stacked(
            [top1, top1 - top2, entropy, counts / MLXArray(Float32(255.0))], axis: -1)
        let pooled = concatenated(
            [h.take(.init(0), axis: 1).asType(.float32), features.asType(.float32)],
            axis: -1)
        let action = actLinear2.apply(
            MLXNN.gelu(actLinear1.apply(pooled.asType(actLinear1.weight.dtype)))
        ).asType(.float32)
        return (logits, action)
    }
}
