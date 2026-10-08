//! Hand-written bindings to the used mlx-c surface (ADR 0051 decision 1:
//! ~60 symbols; a generator pipeline would cost more than it saves at this
//! surface size). Ownership follows mlx-c's rule: constructors hand back a
//! +1 owned handle, every call borrows. [`Array`] is the single owner; the
//! raw handles are `Copy` but only ever freed through [`Drop`].

use std::ffi::c_void;

pub type Status = i32;
pub const MLX_OK: Status = 0;

#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawArray {
    ctx: *mut c_void,
}
#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawStream {
    ctx: *mut c_void,
}
#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawDevice {
    ctx: *mut c_void,
}
#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawMapStringToArray {
    ctx: *mut c_void,
}
#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawMapStringToString {
    ctx: *mut c_void,
}
#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawVectorArray {
    ctx: *mut c_void,
}
#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawClosure {
    ctx: *mut c_void,
}
#[derive(Copy, Clone)]
#[repr(C)]
pub struct RawString {
    ctx: *mut c_void,
}

#[derive(Copy, Clone, PartialEq, Eq, Debug, Hash)]
#[repr(C)]
pub enum Dtype {
    Bool = 0,
    UInt8 = 1,
    UInt16 = 2,
    UInt32 = 3,
    UInt64 = 4,
    Int8 = 5,
    Int16 = 6,
    Int32 = 7,
    Int64 = 8,
    Float16 = 9,
    Float32 = 10,
    Float64 = 11,
    BFloat16 = 12,
    Complex64 = 13,
}

#[derive(Copy, Clone)]
#[repr(C)]
pub struct OptionalFloat {
    pub value: f32,
    pub has_value: bool,
}

/// `mlx_optional_int` (optional.h): `{int value; bool has_value}` — the C
/// value field is a 32-bit int.
#[derive(Copy, Clone)]
#[repr(C)]
pub struct OptionalInt {
    pub value: i32,
    pub has_value: bool,
}

/// `mlx_optional_dtype` (io_types.h).
#[derive(Copy, Clone)]
#[repr(C)]
pub struct OptionalDtype {
    pub value: Dtype,
    pub has_value: bool,
}

pub const MLX_CPU: i32 = 0;
pub const MLX_GPU: i32 = 1;

extern "C" {
    // array.h
    fn mlx_array_free(arr: RawArray) -> Status;
    fn mlx_array_new_data(
        data: *const c_void,
        shape: *const i32,
        dim: i32,
        dtype: Dtype,
    ) -> RawArray;
    fn mlx_array_new_int(val: i32) -> RawArray;
    fn mlx_array_new_float(val: f32) -> RawArray;
    fn mlx_array_new_bool(val: bool) -> RawArray;
    fn mlx_array_dtype(arr: RawArray) -> Dtype;
    fn mlx_array_ndim(arr: RawArray) -> usize;
    fn mlx_array_dim(arr: RawArray, dim: i32) -> i32;
    fn mlx_array_strides(arr: RawArray) -> *const usize;
    fn mlx_array_itemsize(arr: RawArray) -> usize;
    fn mlx_array_eval(arr: RawArray) -> Status;
    fn mlx_array_item_float32(res: *mut f32, arr: RawArray) -> Status;
    fn mlx_array_data_float32(arr: RawArray) -> *const f32;
    fn mlx_array_tostring(res: *mut RawString, arr: RawArray) -> Status;
    fn mlx_string_free(s: RawString) -> Status;

    // device.h / stream.h
    fn mlx_device_new_type(device_type: i32, index: i32) -> RawDevice;
    fn mlx_set_default_device(dev: RawDevice) -> Status;
    fn mlx_get_default_stream(stream: *mut RawStream, dev: RawDevice) -> Status;
    fn mlx_synchronize(stream: RawStream) -> Status;

    // metal.h
    fn mlx_metal_is_available(res: *mut bool) -> Status;
    fn mlx_metal_set_metallib_path(path: *const std::ffi::c_char) -> Status;


    // ops.h — binary elementwise
    fn mlx_add(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    fn mlx_subtract(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    fn mlx_multiply(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    fn mlx_divide(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    fn mlx_maximum(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    fn mlx_minimum(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    fn mlx_less_equal(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    fn mlx_matmul(res: *mut RawArray, a: RawArray, b: RawArray, s: RawStream) -> Status;
    // ops.h — unary
    fn mlx_astype(res: *mut RawArray, a: RawArray, dtype: Dtype, s: RawStream) -> Status;
    fn mlx_abs(res: *mut RawArray, a: RawArray, s: RawStream) -> Status;
    fn mlx_erf(res: *mut RawArray, a: RawArray, s: RawStream) -> Status;
    fn mlx_exp(res: *mut RawArray, a: RawArray, s: RawStream) -> Status;
    fn mlx_log(res: *mut RawArray, a: RawArray, s: RawStream) -> Status;
    fn mlx_sqrt(res: *mut RawArray, a: RawArray, s: RawStream) -> Status;
    // ops.h — reductions (axes variants take int* axes)
    fn mlx_mean(res: *mut RawArray, a: RawArray, keepdims: bool, s: RawStream) -> Status;
    fn mlx_mean_axes(
        res: *mut RawArray,
        a: RawArray,
        axes: *const i32,
        axes_num: usize,
        keepdims: bool,
        s: RawStream,
    ) -> Status;
    fn mlx_sum_axes(
        res: *mut RawArray,
        a: RawArray,
        axes: *const i32,
        axes_num: usize,
        keepdims: bool,
        s: RawStream,
    ) -> Status;
    fn mlx_max_axes(
        res: *mut RawArray,
        a: RawArray,
        axes: *const i32,
        axes_num: usize,
        keepdims: bool,
        s: RawStream,
    ) -> Status;
    fn mlx_softmax(res: *mut RawArray, a: RawArray, precise: bool, s: RawStream) -> Status;
    fn mlx_sigmoid(res: *mut RawArray, a: RawArray, s: RawStream) -> Status;
    fn mlx_argmax_axis(
        res: *mut RawArray,
        a: RawArray,
        axis: i32,
        keepdims: bool,
        s: RawStream,
    ) -> Status;
    // ops.h — quantization (ADR 0054 R2: the same kernels the python
    // reference runtime dispatches; mode strings match mlx's own).
    fn mlx_quantize(
        res: *mut RawVectorArray,
        w: RawArray,
        group_size: OptionalInt,
        bits: OptionalInt,
        mode: *const std::ffi::c_char,
        global_scale: RawArray,
        s: RawStream,
    ) -> Status;
    fn mlx_quantized_matmul(
        res: *mut RawArray,
        x: RawArray,
        w: RawArray,
        scales: RawArray,
        biases: RawArray,
        transpose: bool,
        // ops.h: mlx_optional_int — {int32 value; bool has_value}; plain
        // i32s here scramble the ABI (bits read garbage).
        group_size: crate::mlx::OptionalInt,
        bits: crate::mlx::OptionalInt,
        mode: *const std::ffi::c_char,
        s: RawStream,
    ) -> Status;
    fn mlx_dequantize(
        res: *mut RawArray,
        w: RawArray,
        scales: RawArray,
        biases: RawArray,
        group_size: OptionalInt,
        bits: OptionalInt,
        mode: *const std::ffi::c_char,
        global_scale: RawArray,
        dtype: OptionalDtype,
        s: RawStream,
    ) -> Status;
    fn mlx_sort_axis(res: *mut RawArray, a: RawArray, axis: i32, s: RawStream) -> Status;
    // ops.h — indexing / shape
    fn mlx_take(res: *mut RawArray, a: RawArray, indices: RawArray, s: RawStream) -> Status;
    fn mlx_take_along_axis(
        res: *mut RawArray,
        a: RawArray,
        indices: RawArray,
        axis: i32,
        s: RawStream,
    ) -> Status;
    fn mlx_contiguous(res: *mut RawArray, a: RawArray, allow_col_major: bool, s: RawStream) -> Status;
    fn mlx_transpose(res: *mut RawArray, a: RawArray, s: RawStream) -> Status;
    fn mlx_transpose_axes(
        res: *mut RawArray,
        a: RawArray,
        axes: *const i32,
        axes_num: usize,
        s: RawStream,
    ) -> Status;
    fn mlx_reshape(
        res: *mut RawArray,
        a: RawArray,
        shape: *const i32,
        shape_num: usize,
        s: RawStream,
    ) -> Status;
    fn mlx_expand_dims_axes(
        res: *mut RawArray,
        a: RawArray,
        axes: *const i32,
        axes_num: usize,
        s: RawStream,
    ) -> Status;
    fn mlx_squeeze_axes(
        res: *mut RawArray,
        a: RawArray,
        axes: *const i32,
        axes_num: usize,
        s: RawStream,
    ) -> Status;
    fn mlx_arange(
        res: *mut RawArray,
        start: f64,
        stop: f64,
        step: f64,
        dtype: Dtype,
        s: RawStream,
    ) -> Status;
    fn mlx_full(
        res: *mut RawArray,
        shape: *const i32,
        shape_num: usize,
        vals: RawArray,
        dtype: Dtype,
        s: RawStream,
    ) -> Status;
    // ops.h — vector-array producers
    fn mlx_split(
        res: *mut RawVectorArray,
        a: RawArray,
        num_splits: i32,
        axis: i32,
        s: RawStream,
    ) -> Status;
    fn mlx_concatenate_axis(
        res: *mut RawArray,
        arrays: RawVectorArray,
        axis: i32,
        s: RawStream,
    ) -> Status;
    fn mlx_stack_axis(
        res: *mut RawArray,
        arrays: RawVectorArray,
        axis: i32,
        s: RawStream,
    ) -> Status;
    fn mlx_where(
        res: *mut RawArray,
        condition: RawArray,
        x: RawArray,
        y: RawArray,
        s: RawStream,
    ) -> Status;
    // vector.h
    fn mlx_vector_array_new() -> RawVectorArray;
    fn mlx_vector_array_append_value(vec: RawVectorArray, value: RawArray) -> Status;
    fn mlx_vector_array_get(res: *mut RawArray, vec: RawVectorArray, idx: usize) -> Status;
    fn mlx_vector_array_size(vec: RawVectorArray) -> usize;
    fn mlx_vector_array_free(vec: RawVectorArray) -> Status;
    // closure.h + compile.h (ADR 0054 R1 — fusion without kernels)
    fn mlx_closure_new_func_payload(
        fun: Option<
            unsafe extern "C" fn(
                res: *mut RawVectorArray,
                input: RawVectorArray,
                payload: *mut c_void,
            ) -> Status,
        >,
        payload: *mut c_void,
        dtor: Option<unsafe extern "C" fn(payload: *mut c_void)>,
    ) -> RawClosure;
    fn mlx_closure_apply(
        res: *mut RawVectorArray,
        cls: RawClosure,
        input: RawVectorArray,
    ) -> Status;
    fn mlx_closure_free(cls: RawClosure) -> Status;
    fn mlx_compile(res: *mut RawClosure, fun: RawClosure, shapeless: bool) -> Status;
    fn mlx_vector_array_new_data(data: *const RawArray, size: usize) -> RawVectorArray;
    fn mlx_slice(
        res: *mut RawArray,
        a: RawArray,
        start: *const i32,
        start_num: usize,
        stop: *const i32,
        stop_num: usize,
        strides: *const i32,
        strides_num: usize,
        s: RawStream,
    ) -> Status;
    fn mlx_slice_update(
        res: *mut RawArray,
        src: RawArray,
        update: RawArray,
        start: *const i32,
        start_num: usize,
        stop: *const i32,
        stop_num: usize,
        strides: *const i32,
        strides_num: usize,
        s: RawStream,
    ) -> Status;
    // fast.h
    fn mlx_fast_rms_norm(
        res: *mut RawArray,
        x: RawArray,
        weight: RawArray,
        eps: f32,
        s: RawStream,
    ) -> Status;
    fn mlx_fast_rope(
        res: *mut RawArray,
        x: RawArray,
        dims: i32,
        traditional: bool,
        base: OptionalFloat,
        scale: f32,
        offset: i32,
        freqs: RawArray,
        s: RawStream,
    ) -> Status;
    fn mlx_fast_scaled_dot_product_attention(
        res: *mut RawArray,
        queries: RawArray,
        keys: RawArray,
        values: RawArray,
        scale: f32,
        mask_mode: *const std::ffi::c_char,
        mask_arr: RawArray,
        sinks: RawArray,
        force_fused: bool,
        s: RawStream,
    ) -> Status;
}

/// Block until every op submitted on this stream has executed (profiler
/// section attribution; the golden path never syncs mid-graph).
pub fn synchronize_stream(s: Stream) -> MlxResult<()> {
    chk(unsafe { mlx_synchronize(s.0) })?;
    Ok(())
}

/// A fallible mlx call.
pub type MlxResult<T> = Result<T, MlxError>;

#[derive(Debug)]
pub struct MlxError(pub Status);

fn chk(status: Status) -> MlxResult<()> {
    if status == MLX_OK {
        Ok(())
    } else {
        Err(MlxError(status))
    }
}

/// The one GPU stream this engine uses; created against the default device.
#[derive(Copy, Clone)]
pub struct Stream(RawStream);

pub fn gpu() -> MlxResult<Stream> {
    let mut available = false;
    chk(unsafe { mlx_metal_is_available(&mut available) })?;
    if !available {
        return Err(MlxError(-999));
    }
    let dev = unsafe { mlx_device_new_type(MLX_GPU, 0) };
    chk(unsafe { mlx_set_default_device(dev) })?;
    let mut stream = unsafe { std::mem::zeroed() };
    chk(unsafe { mlx_get_default_stream(&mut stream, dev) })?;
    Ok(Stream(stream))
}

/// Point MLX's Metal kernel library at `path` before the first GPU op.
pub fn set_metallib_path(path: &std::path::Path) -> MlxResult<()> {
    let c = std::ffi::CString::new(path.to_string_lossy().as_bytes())
        .map_err(|_| MlxError(-998))?;
    chk(unsafe { mlx_metal_set_metallib_path(c.as_ptr()) })
}

use crate::safetensors::SafetensorsFile;

pub fn load_safetensors(
    file: &std::path::Path,
    _stream: Stream,
) -> MlxResult<SafetensorsFile> {
    SafetensorsFile::open(file)
}


/// Owned mlx array (+1 reference; freed on drop).
pub struct Array(RawArray);

impl Array {
    pub fn from_data_i32(data: &[i32], shape: &[usize]) -> MlxResult<Array> {
        let shape: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        Ok(Array(unsafe {
            mlx_array_new_data(
                data.as_ptr() as *const c_void,
                shape.as_ptr(),
                shape.len() as i32,
                Dtype::Int32,
            )
        }))
    }

    pub fn from_data_f16(data: &[u8], shape: &[usize]) -> MlxResult<Array> {
        let shape: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        Ok(Array(unsafe {
            mlx_array_new_data(
                data.as_ptr() as *const c_void,
                shape.as_ptr(),
                shape.len() as i32,
                Dtype::Float16,
            )
        }))
    }

    pub fn from_data_bool(data: &[u8], shape: &[usize]) -> MlxResult<Array> {
        let shape: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        Ok(Array(unsafe {
            mlx_array_new_data(
                data.as_ptr() as *const c_void,
                shape.as_ptr(),
                shape.len() as i32,
                Dtype::Bool,
            )
        }))
    }

    /// Packed quantized weights (safetensors "U32") — host copy, no stream.
    pub fn from_data_u32(data: &[u32], shape: &[usize]) -> MlxResult<Array> {
        let shape: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        Ok(Array(unsafe {
            mlx_array_new_data(
                data.as_ptr() as *const c_void,
                shape.as_ptr(),
                shape.len() as i32,
                Dtype::UInt32,
            )
        }))
    }

    /// bfloat16 raw bytes (safetensors "BF16", u16 little-endian) — host copy.
    pub fn from_data_bf16(data: &[u8], shape: &[usize]) -> MlxResult<Array> {
        let shape: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        Ok(Array(unsafe {
            mlx_array_new_data(
                data.as_ptr() as *const c_void,
                shape.as_ptr(),
                shape.len() as i32,
                Dtype::BFloat16,
            )
        }))
    }

    pub fn from_data_f32(data: &[f32], shape: &[usize]) -> MlxResult<Array> {
        let shape: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        Ok(Array(unsafe {
            mlx_array_new_data(
                data.as_ptr() as *const c_void,
                shape.as_ptr(),
                shape.len() as i32,
                Dtype::Float32,
            )
        }))
    }

    pub fn scalar_f32(v: f32) -> Array {
        Array(unsafe { mlx_array_new_float(v) })
    }

    pub fn scalar_i32(v: i32) -> Array {
        Array(unsafe { mlx_array_new_int(v) })
    }

    pub fn scalar_bool(v: bool) -> Array {
        Array(unsafe { mlx_array_new_bool(v) })
    }

    pub fn arange_i32(start: i32, stop: i32, stream: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_arange(
                &mut out,
                start as f64,
                stop as f64,
                1.0,
                Dtype::Int32,
                stream.0,
            )
        })?;
        Ok(Array(out))
    }

    pub fn full_f32(v: f64, shape: &[usize], stream: Stream) -> MlxResult<Array> {
        Self::full(v, shape, Dtype::Float32, stream)
    }

    pub fn full(v: f64, shape: &[usize], dtype: Dtype, stream: Stream) -> MlxResult<Array> {
        let shape_v: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        let vals = match dtype {
            Dtype::Bool => Array::scalar_bool(v != 0.0),
            Dtype::Int32 => Array::scalar_i32(v as i32),
            _ => Array::scalar_f32(v as f32),
        };
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_full(
                &mut out,
                shape_v.as_ptr(),
                shape_v.len() as usize,
                vals.0,
                dtype,
                stream.0,
            )
        })?;
        Ok(Array(out))
    }

    pub fn dtype(&self) -> Dtype {
        unsafe { mlx_array_dtype(self.0) }
    }

    pub fn ndim(&self) -> usize {
        unsafe { mlx_array_ndim(self.0) }
    }

    pub fn dim(&self, i: i32) -> usize {
        unsafe { mlx_array_dim(self.0, i) as usize }
    }

    pub fn eval(&self) -> MlxResult<()> {
        chk(unsafe { mlx_array_eval(self.0) })
    }

    /// Scalar value of a 0-d array (forces sync).
    pub fn item_f32(&self) -> MlxResult<f32> {
        let mut out = 0.0f32;
        chk(unsafe { mlx_array_item_float32(&mut out, self.0) })?;
        Ok(out)
    }

    pub fn tostring(&self) -> String {
        let mut s = unsafe { std::mem::zeroed() };
        if unsafe { mlx_array_tostring(&mut s, self.0) } != MLX_OK {
            return String::from("<tostring failed>");
        }
        unsafe {
            let ptr = s.ctx as *const u8;
            let mut len = 0usize;
            while *ptr.add(len) != 0 {
                len += 1;
            }
            let bytes = std::slice::from_raw_parts(ptr, len);
            let out = String::from_utf8_lossy(bytes).to_string();
            mlx_string_free(s);
            out
        }
    }

    /// The borrowed raw handle (for C calls taking arrays by value).
    pub(crate) fn raw(&self) -> RawArray {
        self.0
    }

    // ---- elementwise ----
    pub fn add(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_add(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn sub(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_subtract(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn mul(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_multiply(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn div(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_divide(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn max_elemwise(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_maximum(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn min_elemwise(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_minimum(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn less_equal(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_less_equal(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn matmul(&self, other: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_matmul(&mut out, self.0, other.0, s.0) })?;
        Ok(Array(out))
    }

    // ---- unary ----
    pub fn astype(&self, dtype: Dtype, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_astype(&mut out, self.0, dtype, s.0) })?;
        Ok(Array(out))
    }

    /// Owned passthrough reference (+1): mlx astype returns the same array
    /// when the dtype already matches. This is the layer-0 identity norm
    /// path (attnNorm == nil in the reference port).
    pub fn identity(&self, s: Stream) -> MlxResult<Array> {
        self.astype(self.dtype(), s)
    }

    pub fn abs(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_abs(&mut out, self.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn erf(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_erf(&mut out, self.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn sigmoid(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_sigmoid(&mut out, self.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn argmax_axis(&self, axis: i32, keepdims: bool, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_argmax_axis(&mut out, self.0, axis, keepdims, s.0) })?;
        Ok(Array(out))
    }

    pub fn exp(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_exp(&mut out, self.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn log(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_log(&mut out, self.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn sqrt(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_sqrt(&mut out, self.0, s.0) })?;
        Ok(Array(out))
    }

    // ---- reductions ----
    pub fn mean_all(&self, keepdims: bool, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_mean(&mut out, self.0, keepdims, s.0) })?;
        Ok(Array(out))
    }

    pub fn mean_axes(
        &self,
        axes: &[i32],
        keepdims: bool,
        s: Stream,
    ) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_mean_axes(&mut out, self.0, axes.as_ptr(), axes.len(), keepdims, s.0)
        })?;
        Ok(Array(out))
    }

    pub fn sum_axes(&self, axes: &[i32], keepdims: bool, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_sum_axes(&mut out, self.0, axes.as_ptr(), axes.len(), keepdims, s.0)
        })?;
        Ok(Array(out))
    }

    pub fn softmax(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_softmax(&mut out, self.0, false, s.0) })?;
        Ok(Array(out))
    }

    pub fn sort_axis(&self, axis: i32, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_sort_axis(&mut out, self.0, axis, s.0) })?;
        Ok(Array(out))
    }

    // ---- indexing / shape ----
    pub fn take(&self, indices: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_take(&mut out, self.0, indices.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn take_along_axis(&self, indices: &Array, axis: i32, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_take_along_axis(&mut out, self.0, indices.0, axis, s.0) })?;
        Ok(Array(out))
    }

    pub fn transpose_all(&self, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_transpose(&mut out, self.0, s.0) })?;
        Ok(Array(out))
    }

    pub fn transpose_axes(&self, axes: &[i32], s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_transpose_axes(&mut out, self.0, axes.as_ptr(), axes.len(), s.0) })?;
        Ok(Array(out))
    }

    pub fn reshape(&self, shape: &[usize], s: Stream) -> MlxResult<Array> {
        let shape_v: Vec<i32> = shape.iter().map(|d| *d as i32).collect();
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_reshape(&mut out, self.0, shape_v.as_ptr(), shape_v.len(), s.0)
        })?;
        Ok(Array(out))
    }

    pub fn expand_dims(&self, axes: &[i32], s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_expand_dims_axes(&mut out, self.0, axes.as_ptr(), axes.len(), s.0)
        })?;
        Ok(Array(out))
    }

    pub fn squeeze_axes(&self, axes: &[i32], s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_squeeze_axes(&mut out, self.0, axes.as_ptr(), axes.len(), s.0)
        })?;
        Ok(Array(out))
    }

    pub fn split_n(&self, num_splits: i32, axis: i32, s: Stream) -> MlxResult<Vec<Array>> {
        let mut vec = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_split(&mut vec, self.0, num_splits, axis, s.0) })?;
        let out = (|| {
            let mut parts = Vec::new();
            for i in 0..num_splits {
                let mut a = unsafe { std::mem::zeroed() };
                chk(unsafe { mlx_vector_array_get(&mut a, vec, i as usize) })?;
                parts.push(Array(a));
            }
            Ok(parts)
        })();
        unsafe { mlx_vector_array_free(vec) };
        out
    }

    pub fn split2(&self, axis: i32, s: Stream) -> MlxResult<(Array, Array)> {
        let mut vec = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_split(&mut vec, self.0, 2, axis, s.0) })?;
        let out = (|| {
            let mut a = unsafe { std::mem::zeroed() };
            let mut b = unsafe { std::mem::zeroed() };
            chk(unsafe { mlx_vector_array_get(&mut a, vec, 0) })?;
            chk(unsafe { mlx_vector_array_get(&mut b, vec, 1) })?;
            Ok((Array(a), Array(b)))
        })();
        unsafe { mlx_vector_array_free(vec) };
        out
    }

    pub fn concatenate_axis(arrays: &[&Array], axis: i32, s: Stream) -> MlxResult<Array> {
        let vec = unsafe { mlx_vector_array_new() };
        for a in arrays {
            chk(unsafe { mlx_vector_array_append_value(vec, a.0) })?;
        }
        let mut out = unsafe { std::mem::zeroed() };
        let result = chk(unsafe { mlx_concatenate_axis(&mut out, vec, axis, s.0) });
        unsafe { mlx_vector_array_free(vec) };
        result?;
        Ok(Array(out))
    }

    pub fn stack_axis(arrays: &[&Array], axis: i32, s: Stream) -> MlxResult<Array> {
        let vec = unsafe { mlx_vector_array_new() };
        for a in arrays {
            chk(unsafe { mlx_vector_array_append_value(vec, a.0) })?;
        }
        let mut out = unsafe { std::mem::zeroed() };
        let result = chk(unsafe { mlx_stack_axis(&mut out, vec, axis, s.0) });
        unsafe { mlx_vector_array_free(vec) };
        result?;
        Ok(Array(out))
    }

    pub fn where_(cond: &Array, x: &Array, y: &Array, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_where(&mut out, cond.0, x.0, y.0, s.0) })?;
        Ok(Array(out))
    }

    // ---- fast ops ----
    pub fn rope(
        &self,
        dims: i32,
        base: f32,
        offset: i32,
        s: Stream,
    ) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_fast_rope(
                &mut out,
                self.0,
                dims,
                false,
                OptionalFloat {
                    value: base,
                    has_value: true,
                },
                1.0,
                offset,
                std::mem::zeroed(),
                s.0,
            )
        })?;
        Ok(Array(out))
    }

    pub fn sdp_attention(
        q: &Array,
        k: &Array,
        v: &Array,
        scale: f32,
        mask: &Array,
        s: Stream,
    ) -> MlxResult<Array> {
        Self::sdp_attention_mode(q, k, v, scale, "", Some(mask), s)
    }

    /// Mask-mode-aware sdpa: `""` applies a bool keep-mask array, `"causal"`
    /// uses the kernel's native causal path (what python mlx-lm passes for
    /// prefill), `None` mask with `""` is the no-mask decode call.
    pub fn sdp_attention_mode(
        q: &Array,
        k: &Array,
        v: &Array,
        scale: f32,
        mode: &str,
        mask: Option<&Array>,
        s: Stream,
    ) -> MlxResult<Array> {
        let mut mode_c = mode.as_bytes().to_vec();
        mode_c.push(0);
        // mlx-swift passes the mask with an empty mode string — the C++
        // sdpa then applies the bool array directly (keep-mask semantics).
        // The explicit "array" mode takes a different (additive-float)
        // path and diverges numerically.
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_fast_scaled_dot_product_attention(
                &mut out,
                q.0,
                k.0,
                v.0,
                scale,
                mode_c.as_ptr() as *const std::ffi::c_char,
                mask.map(|m| m.0).unwrap_or(std::mem::zeroed()),
                std::mem::zeroed(),
                false,
                s.0,
            )
        })?;
        Ok(Array(out))
    }

    /// `mx.slice` — a strided view (no copy).
    pub fn slice(
        &self,
        start: &[i32],
        stop: &[i32],
        strides: &[i32],
        s: Stream,
    ) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_slice(
                &mut out,
                self.0,
                start.as_ptr(),
                start.len(),
                stop.as_ptr(),
                stop.len(),
                strides.as_ptr(),
                strides.len(),
                s.0,
            )
        })?;
        Ok(Array(out))
    }

    /// `mx.slice_update` — the functional form of python's
    /// `buf[..., a:b, :] = update` (one GPU op, no host copy).
    pub fn slice_update(
        src: &Array,
        update: &Array,
        start: &[i32],
        stop: &[i32],
        strides: &[i32],
        s: Stream,
    ) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_slice_update(
                &mut out,
                src.0,
                update.0,
                start.as_ptr(),
                start.len(),
                stop.as_ptr(),
                stop.len(),
                strides.as_ptr(),
                strides.len(),
                s.0,
            )
        })?;
        Ok(Array(out))
    }

    /// `mx.fast.rms_norm` — what `nn.RMSNorm.__call__` runs (fp32 mean
    /// accumulation inside the fused kernel).
    pub fn rms_norm(x: &Array, weight: &Array, eps: f32, s: Stream) -> MlxResult<Array> {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_fast_rms_norm(&mut out, x.0, weight.0, eps, s.0) })?;
        Ok(Array(out))
    }

    /// `mx.quantize` (affine) → [w U32 packed, scales, biases] — the R3
    /// calibration entry (q8 laya). Group 64, bits 8 in our use.
    pub fn quantize(
        w: &Array,
        group_size: i32,
        bits: i32,
        s: Stream,
    ) -> MlxResult<Vec<Array>> {
        let mode = b"affine\0";
        let mut vec = unsafe { mlx_vector_array_new() };
        chk(unsafe {
            mlx_quantize(
                &mut vec,
                w.0,
                OptionalInt { value: group_size, has_value: true },
                OptionalInt { value: bits, has_value: true },
                mode.as_ptr() as *const std::ffi::c_char,
                std::mem::zeroed(),
                s.0,
            )
        })?;
        let n = unsafe { mlx_vector_array_size(vec) };
        let mut outs = Vec::with_capacity(n);
        for i in 0..n {
            let mut a = unsafe { std::mem::zeroed() };
            chk(unsafe { mlx_vector_array_get(&mut a, vec, i) })?;
            outs.push(Array(a));
        }
        unsafe { mlx_vector_array_free(vec) };
        if outs.len() != 3 {
            return Err(MlxError(-978));
        }
        Ok(outs)
    }

    /// `mx.quantized_matmul(..., transpose, group_size, bits, mode="affine")`
    /// — the exact call `nn.QuantizedLinear` and `QuantizedEmbedding.as_linear`
    /// make. `w` is [out, in] packed U32 when `transpose` is true.
    #[allow(clippy::too_many_arguments)]
    pub fn quantized_matmul(
        x: &Array,
        w: &Array,
        scales: &Array,
        biases: &Array,
        transpose: bool,
        group_size: i32,
        bits: i32,
        s: Stream,
    ) -> MlxResult<Array> {
        let mode = b"affine\0";
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_quantized_matmul(
                &mut out,
                x.0,
                w.0,
                scales.0,
                biases.0,
                transpose,
                OptionalInt { value: group_size, has_value: true },
                OptionalInt { value: bits, has_value: true },
                mode.as_ptr() as *const std::ffi::c_char,
                s.0,
            )
        })?;
        Ok(Array(out))
    }

    /// `mx.dequantize` (affine) — what `QuantizedEmbedding.__call__` runs on
    /// its gathered rows.
    pub fn dequantize(
        w: &Array,
        scales: &Array,
        biases: &Array,
        group_size: i32,
        bits: i32,
        s: Stream,
    ) -> MlxResult<Array> {
        let mode = b"affine\0";
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe {
            mlx_dequantize(
                &mut out,
                w.0,
                scales.0,
                biases.0,
                OptionalInt { value: group_size, has_value: true },
                OptionalInt { value: bits, has_value: true },
                mode.as_ptr() as *const std::ffi::c_char,
                std::mem::zeroed(),
                OptionalDtype { value: Dtype::Float32, has_value: false },
                s.0,
            )
        })?;
        Ok(Array(out))
    }

    /// Bulk float32 readback: eval + one sync, then copy from the
    /// materialized buffer. The array must already be Float32 (the model's
    /// outputs are cast before this is called).
    pub fn to_f32_vec(&self, s: Stream) -> MlxResult<Vec<f32>> {
        if self.dtype() != Dtype::Float32 {
            return Err(MlxError(-997));
        }
        self.eval()?;
        // The C API returns a pointer into physical storage, not a logical
        // flat array. Strides are size_t counts of ELEMENTS (array.h), and
        // can encode reverse views. Never turn an arbitrary view into a
        // shape-product Rust slice: let MLX materialize logical row order.
        let contiguous;
        let source = if self.is_row_contiguous()? {
            self
        } else {
            let mut out = unsafe { std::mem::zeroed() };
            chk(unsafe { mlx_contiguous(&mut out, self.0, false, s.0) })?;
            contiguous = Array(out);
            contiguous.eval()?;
            if !contiguous.is_row_contiguous()? {
                return Err(MlxError(-995));
            }
            &contiguous
        };
        chk(unsafe { mlx_synchronize(s.0) })?;
        let count = (0..source.ndim()).try_fold(1usize, |count, d| {
            count.checked_mul(source.dim(d as i32)).ok_or(MlxError(-995))
        })?;
        if count == 0 {
            return Ok(Vec::new());
        }
        let ptr = unsafe { mlx_array_data_float32(source.0) };
        if ptr.is_null() {
            return Err(MlxError(-996));
        }
        Ok(unsafe { std::slice::from_raw_parts(ptr, count) }.to_vec())
    }

    fn is_row_contiguous(&self) -> MlxResult<bool> {
        let ndim = self.ndim();
        if ndim == 0 { return Ok(true); }
        let strides = unsafe { mlx_array_strides(self.0) };
        if strides.is_null() { return Err(MlxError(-996)); }
        let strides = unsafe { std::slice::from_raw_parts(strides, ndim) };
        let mut expected = 1usize;
        for dim in (0..ndim).rev() {
            let size = self.dim(dim as i32);
            if size > 1 && strides[dim] != expected { return Ok(false); }
            expected = expected.checked_mul(size).ok_or(MlxError(-995))?;
        }
        Ok(true)
    }
}

impl Drop for Array {
    fn drop(&mut self) {
        unsafe { mlx_array_free(self.0) };
    }
}

impl std::fmt::Display for MlxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "mlx status {}", self.0)
    }
}

// SAFETY: mlx arrays/streams are refcounted C++ objects usable from any
// thread; the raw handle is an opaque pointer. `Array` keeps ownership
// unique, `Stream` is Copy as in mlx-c.
unsafe impl Send for RawArray {}
unsafe impl Sync for RawArray {}
unsafe impl Send for RawStream {}
unsafe impl Sync for RawStream {}
unsafe impl Send for RawClosure {}
unsafe impl Sync for RawClosure {}

/// A mlx compiled closure (ADR 0054 R1): wraps a Rust `Fn(&[&Array]) ->
/// Vec<Array>` behind `mlx_closure_new_func_payload` + `mlx_compile`. The
/// first apply per input-shape signature traces the function; mlx fuses the
/// recorded graph and replays the fused kernel sequence on later calls.
pub struct CompiledClosure {
    raw: RawClosure,
}

unsafe extern "C" fn trampoline(
    res: *mut RawVectorArray,
    input: RawVectorArray,
    payload: *mut c_void,
) -> Status {
    let payload = payload as *mut Box<dyn Fn(&[&Array]) -> MlxResult<Vec<Array>> + Send + Sync>;
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let n = unsafe { mlx_vector_array_size(input) };
        let mut arrays = Vec::with_capacity(n);
        for i in 0..n {
            let mut a = unsafe { std::mem::zeroed() };
            chk(unsafe { mlx_vector_array_get(&mut a, input, i) })?;
            arrays.push(Array(a));
        }
        let refs: Vec<&Array> = arrays.iter().collect();
        (*payload)(&refs)
    }));
    match result {
        Ok(Ok(outs)) => {
            let raws: Vec<RawArray> = outs.iter().map(|a| a.raw()).collect();
            let vec = unsafe { mlx_vector_array_new_data(raws.as_ptr(), raws.len()) };
            unsafe { *res = vec };
            MLX_OK
        }
        Ok(Err(e)) => e.0,
        Err(_) => -976, // panic inside the traced closure
    }
}

unsafe extern "C" fn payload_dtor(payload: *mut c_void) {
    drop(Box::from_raw(
        payload as *mut Box<dyn Fn(&[&Array]) -> MlxResult<Vec<Array>> + Send + Sync>,
    ));
}

impl CompiledClosure {
    /// Compiles `f`. `shapeless=false`: mlx specializes per input-shape
    /// signature and caches internally (right for laya — shapes repeat, and
    /// shapeless tracing has restrictions we do not need).
    pub fn compile<F>(f: F) -> MlxResult<CompiledClosure>
    where
        F: Fn(&[&Array]) -> MlxResult<Vec<Array>> + Send + Sync + 'static,
    {
        let boxed: Box<dyn Fn(&[&Array]) -> MlxResult<Vec<Array>> + Send + Sync> = Box::new(f);
        let payload = Box::into_raw(Box::new(boxed));
        let raw = unsafe {
            mlx_closure_new_func_payload(Some(trampoline), payload as *mut c_void, Some(payload_dtor))
        };
        let mut compiled = unsafe { std::mem::zeroed() };
        if let Err(e) = chk(unsafe { mlx_compile(&mut compiled, raw, false) }) {
            // The payload's only owner is `raw`; freeing it runs the dtor.
            unsafe { mlx_closure_free(raw) };
            return Err(e);
        }
        chk(unsafe { mlx_closure_free(raw) })?;
        Ok(CompiledClosure { raw: compiled })
    }

    /// Applies the compiled closure. Outputs arrive unmaterialized (lazy),
    /// exactly like the eager walk's.
    pub fn apply(&self, inputs: &[&Array]) -> MlxResult<Vec<Array>> {
        let vec = unsafe { mlx_vector_array_new() };
        for a in inputs {
            chk(unsafe { mlx_vector_array_append_value(vec, a.raw()) })?;
        }
        let mut res = unsafe { std::mem::zeroed() };
        let status = chk(unsafe { mlx_closure_apply(&mut res, self.raw, vec) });
        unsafe { mlx_vector_array_free(vec) };
        status?;
        let n = unsafe { mlx_vector_array_size(res) };
        let mut outs = Vec::with_capacity(n);
        for i in 0..n {
            let mut a = unsafe { std::mem::zeroed() };
            chk(unsafe { mlx_vector_array_get(&mut a, res, i) })?;
            outs.push(Array(a));
        }
        unsafe { mlx_vector_array_free(res) };
        Ok(outs)
    }
}

impl Drop for CompiledClosure {
    fn drop(&mut self) {
        // The compiled closure holds the payload via shared_ptr — freeing it
        // runs our dtor exactly once.
        unsafe { mlx_closure_free(self.raw) };
    }
}

// SAFETY: the payload box is Send+Sync by bound, and the mlx closure ctx is
// a refcounted C++ object; applies are serialized by the engine's forward
// lock (lib.rs), matching the eager path's threading contract.
unsafe impl Send for CompiledClosure {}
unsafe impl Sync for CompiledClosure {}



#[cfg(test)]
mod host_marshalling_tests {
    use super::*;

    extern "C" {
        fn mlx_slice(res: *mut RawArray, a: RawArray,
            start: *const i32, start_num: usize,
            stop: *const i32, stop_num: usize,
            strides: *const i32, strides_num: usize, s: RawStream) -> Status;
    }

    fn slice(a: &Array, start: &[i32], stop: &[i32], strides: &[i32], s: Stream) -> Array {
        let mut out = unsafe { std::mem::zeroed() };
        chk(unsafe { mlx_slice(&mut out, a.0, start.as_ptr(), start.len(),
            stop.as_ptr(), stop.len(), strides.as_ptr(), strides.len(), s.0) }).unwrap();
        Array(out)
    }

    #[test]
    fn logical_host_copy_handles_transpose_slice_reverse_and_scalar() {
        if std::env::var("LAYA_NATIVE_TEST").as_deref() != Ok("1") { return; }
        let metal = std::env::var("LAYA_METALLIB").expect("explicit native test metallib");
        set_metallib_path(std::path::Path::new(&metal)).unwrap();
        let s = gpu().unwrap();
        let flat = Array::arange_i32(0, 6, s).unwrap().astype(Dtype::Float32, s).unwrap();
        let matrix = flat.reshape(&[2, 3], s).unwrap();
        assert_eq!(matrix.to_f32_vec(s).unwrap(), vec![0., 1., 2., 3., 4., 5.]);
        let transpose = matrix.transpose_axes(&[1, 0], s).unwrap();
        assert_eq!(transpose.to_f32_vec(s).unwrap(), vec![0., 3., 1., 4., 2., 5.]);
        let sparse = slice(&matrix, &[0, 0], &[2, 3], &[1, 2], s);
        assert_eq!(sparse.to_f32_vec(s).unwrap(), vec![0., 2., 3., 5.]);
        let reverse = slice(&flat, &[5], &[-7], &[-1], s);
        assert_eq!(reverse.to_f32_vec(s).unwrap(), vec![5., 4., 3., 2., 1., 0.]);
        assert_eq!(Array::scalar_f32(7.).to_f32_vec(s).unwrap(), vec![7.]);
    }
}
