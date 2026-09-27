//! `uia-sidecar/1` — Windows UI Automation sidecar.
//!
//! Same wire discipline as `xs-webrtc-sidecar/1` (ADR 0037): handshake
//! line first, then JSON-lines requests (`id`, `op`) and events. Ops:
//! `ping`, `snapshot` (full UIA tree as a semantic snapshot), `invoke`
//! (InvokePattern click on a node id), `shutdown`.
//!
//! Windows-only: `main.rs` compiles everywhere, but the real engine is
//! gated `#[cfg(windows)]` — non-Windows builds answer every op with an
//! error so a misrouted sidecar fails loudly instead of silently.

use anyhow::Result;
use serde_json::{json, Value};

fn main() -> Result<()> {
    println!("{{\"sidecar\":\"uia-sidecar/1\"}}");
    let mut input = String::new();
    loop {
        input.clear();
        let bytes = std::io::stdin().read_line(&mut input)?;
        if bytes == 0 {
            break;
        }
        let Ok(message) = serde_json::from_str::<Value>(input.trim()) else {
            continue;
        };
        let Some(id) = message.get("id").and_then(Value::as_i64) else {
            continue;
        };
        let op = message.get("op").and_then(Value::as_str).unwrap_or("");
        let response = match handle_op(op, &message) {
            Ok(value) => json!({"id": id, "result": value}),
            Err(error) => json!({"id": id, "error": error.to_string()}),
        };
        println!("{response}");
        if op == "shutdown" {
            break;
        }
    }
    Ok(())
}

#[cfg(windows)]
fn handle_op(op: &str, message: &Value) -> Result<Value> {
    windows_impl::handle_op(op, message)
}

#[cfg(windows)]
mod windows_impl {
    use anyhow::Result;
    use serde_json::{json, Value};
    use windows::Win32::UI::Accessibility::{
        CUIAutomation, IUIAutomation, IUIAutomationElement,
    };
    use windows::Win32::System::Com::{
        CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER,
        COINIT_MULTITHREADED,
    };
    use windows::core::Interface;

    fn automation() -> Result<IUIAutomation> {
        unsafe {
            CoInitializeEx(None, COINIT_MULTITHREADED)?;
            let automation: IUIAutomation =
                CoCreateInstance(&CUIAutomation, None, CLSCTX_INPROC_SERVER)?;
            Ok(automation)
        }
    }

    fn element_name(element: &IUIAutomationElement) -> String {
        unsafe {
            element
                .CurrentName()
                .map(|name| name.to_string())
                .unwrap_or_default()
        }
    }

    fn element_type_id(element: &IUIAutomationElement) -> i32 {
        unsafe { element.CurrentControlType().unwrap_or_default() }
    }

    fn walk(
        element: &IUIAutomation,
        parent: &IUIAutomationElement,
        id: &mut i32,
        nodes: &mut Vec<Value>,
    ) -> Result<Value> {
        let node_id = *id;
        *id += 1;
        let mut children = Vec::new();
        let walker = element.get_ControlViewWalker()?;
        let mut child = walker.GetFirstChildElement(parent)?;
        while let Some(current) = child {
            children.push(walk(element, &current, id, nodes)?);
            child = walker.GetNextSiblingElement(&current)?;
        }
        // Control-type ids map onto the family's role vocabulary on the
        // Dart side; the raw id is preserved for exactness.
        Ok(json!({
            "id": node_id,
            "name": element_name(parent),
            "controlType": element_type_id(parent),
            "children": children,
        }))
    }

    pub fn handle_op(op: &str, message: &Value) -> Result<Value> {
        match op {
            "ping" => Ok(json!({"pong": true, "platform": "windows"})),
            "snapshot" => {
                let element = automation()?;
                let root = element.GetRootElement()?;
                let mut id = 0;
                let mut nodes = Vec::new();
                let tree = walk(&element, &root, &mut id, &mut nodes)?;
                Ok(json!({"root": tree}))
            }
            "invoke" => {
                let element = automation()?;
                let root = element.GetRootElement()?;
                let target_name = message["name"].as_str().unwrap_or("");
                let found = find_by_name(&element, &root, target_name)?;
                match found {
                    Some(matched) => {
                        let invoke: IUIAutomationInvokePattern =
                            matched
                                .GetCurrentPattern(
                                    windows::Win32::UI::Accessibility::
                                        UIA_InvokePatternId,
                                )?
                                .and_then(|pattern| pattern.cast().ok())
                                .ok_or_else(|| {
                                    anyhow::anyhow!(
                                        "element has no InvokePattern"
                                    )
                                })?;
                        invoke.Invoke()?;
                        Ok(json!({"invoked": target_name}))
                    }
                    None => Err(anyhow::anyhow!(
                        "no element named {target_name}"
                    )),
                }
            }
            "shutdown" => Ok(json!({"bye": true})),
            other => Err(anyhow::anyhow!("unknown op: {other}")),
        }
    }

    fn find_by_name(
        element: &IUIAutomation,
        parent: &IUIAutomationElement,
        name: &str,
    ) -> Result<Option<IUIAutomationElement>> {
        if element_name(parent) == name {
            return Ok(Some(parent.clone()));
        }
        let walker = element.get_ControlViewWalker()?;
        let mut child = walker.GetFirstChildElement(parent)?;
        while let Some(current) = child {
            if let Some(found) = find_by_name(element, &current, name)? {
                return Ok(Some(found));
            }
            child = walker.GetNextSiblingElement(&current)?;
        }
        Ok(None)
    }
}

#[cfg(not(windows))]
fn handle_op(_op: &str, _message: &Value) -> Result<Value> {
    Err(anyhow::anyhow!(
        "uia-sidecar requires Windows; this binary was built for a \
         non-Windows target"
    ))
}
