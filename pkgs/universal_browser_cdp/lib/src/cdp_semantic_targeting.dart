import 'dart:async';
import 'dart:convert';

import 'package:universal_automation_interface/universal_automation_interface.dart';

import 'cdp_page.dart';

/// Fresh, exact semantic targeting. Flutter proxy nodes are accepted only when
/// the center hits the rendering surface in the same Flutter glass pane.
/// The generic DOM actionability path continues to reject unrelated occluders.
class CdpSemanticTargeting implements TargetedAutomationDriver {
  /// Creates targeting over an already-owned page; owns no browser lifecycle.
  CdpSemanticTargeting(
    this.page, {
    this.timeout = const Duration(seconds: 3),
    this.pollInterval = const Duration(milliseconds: 50),
  });

  /// Borrowed page facade.
  final CdpPage page;

  /// Total bound for target readiness.
  final Duration timeout;

  /// Delay between readiness observations.
  final Duration pollInterval;

  Future<Map<String, Object?>> _probe(
    SemanticTarget target, {
    bool focus = false,
  }) async {
    final node = resolveSemanticTarget(
      await page.accessibilitySnapshot(),
      target,
    );
    if (node.attributes['disabled'] == 'true') {
      return {'state': 'disabled'};
    }
    final id = int.tryParse(node.attributes['cdp.backendDOMNodeId'] ?? '');
    if (id == null) {
      throw const ProtocolException('semantic target has no DOM handle');
    }
    final result = await page.connection.send('DOM.resolveNode', {
      'backendNodeId': id,
    });
    final objectId = (result['object'] as Map<String, Object?>?)?['objectId'];
    if (objectId is! String) return _liveProbe(target, focus: focus);
    try {
      final response = await page.connection.send('Runtime.callFunctionOn', {
        'objectId': objectId,
        'functionDeclaration': focus ? _focusProbe : _pointerProbe,
        'returnByValue': true,
      });
      final raw = (response['result'] as Map<String, Object?>?)?['value'];
      if (raw is String) {
        final decoded = jsonDecode(raw) as Map<String, Object?>;
        if (decoded['state'] == 'detached') {
          return await _liveProbe(target, focus: focus);
        }
        return _normalizeProbe(decoded);
      }
      throw const ProtocolException('semantic target returned no probe');
    } finally {
      await page.connection.send('Runtime.releaseObject', {
        'objectId': objectId,
      });
    }
  }

  Future<Map<String, Object?>> _liveProbe(
    SemanticTarget target, {
    required bool focus,
  }) async {
    final raw = await page.evaluate(_liveTargetProbe(target, focus: focus));
    if (raw is! String) {
      throw const ProtocolException('live target returned no probe');
    }
    final decoded = jsonDecode(raw) as Map<String, Object?>;
    if (decoded['state'] == 'ambiguous' || decoded['state'] == 'missing') {
      throw TargetResolutionException(target, decoded['count']! as int);
    }
    return _normalizeProbe(decoded);
  }

  Map<String, Object?> _normalizeProbe(Map<String, Object?> value) =>
      value.containsKey('state')
      ? value
      : {...value, 'state': value['hitOk'] == true ? 'ready' : 'detached'};

  @override
  Future<void> clickTarget(SemanticTarget target) async {
    final clock = Stopwatch()..start();
    String? previous;
    var lastState = 'unknown';
    while (clock.elapsed < timeout) {
      Map<String, Object?> result;
      try {
        result = await _probe(target).timeout(timeout - clock.elapsed);
      } on TargetResolutionException catch (error) {
        // UI state may precede its AX projection. Poll only an absent target;
        // multiple matches remain an immediate refusal before input.
        if (error.details['count'] != 0) rethrow;
        result = {'state': 'missing'};
      } on TimeoutException {
        break;
      }
      lastState = result['state']?.toString() ?? 'unknown';
      if (lastState == 'ready') {
        final key =
            '${result['x']}/${result['y']}/${result['width']}/${result['height']}';
        if (key == previous) {
          await page.clickAt(
            (result['x']! as num).toDouble() +
                (result['width']! as num).toDouble() / 2,
            (result['y']! as num).toDouble() +
                (result['height']! as num).toDouble() / 2,
          );
          return; // Never replay after dispatch, even if its response is lost.
        }
        previous = key;
      } else {
        previous = null;
      }
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < pollInterval ? remaining : pollInterval,
      );
    }
    throw ProtocolException(
      'semantic target not actionable',
      details: {'target': target.toJson(), 'state': lastState},
    );
  }

  @override
  Future<void> focusTarget(SemanticTarget target) async {
    final clock = Stopwatch()..start();
    var lastState = 'unknown';
    while (clock.elapsed < timeout) {
      Map<String, Object?> result;
      try {
        result = await _probe(
          target,
          focus: true,
        ).timeout(timeout - clock.elapsed);
      } on TargetResolutionException catch (error) {
        // UI state may precede its AX projection. Poll only an absent target;
        // multiple matches remain an immediate refusal before input.
        if (error.details['count'] != 0) rethrow;
        result = {'state': 'missing'};
      } on TimeoutException {
        break;
      }
      lastState = result['state']?.toString() ?? 'unknown';
      if (lastState == 'focused') return;
      if (lastState != 'disabled' &&
          lastState != 'detached' &&
          lastState != 'missing') {
        break;
      }
      final remaining = timeout - clock.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(
        remaining < pollInterval ? remaining : pollInterval,
      );
    }
    throw ProtocolException(
      'semantic target did not receive element focus',
      details: {'target': target.toJson(), 'state': lastState},
    );
  }
}

const _elementPrelude = '''
let el = this;
if (el && el.nodeType === 3) el = el.parentElement;
if (!el || !el.isConnected) return JSON.stringify({state: 'detached'});
if (el.matches(':disabled') || el.getAttribute('aria-disabled') === 'true')
  return JSON.stringify({state: 'disabled'});
''';

const _focusProbe =
    '''
function() {
$_elementPrelude
const control = el.matches('input,textarea,select,button,[tabindex]') ? el :
  el.querySelector('input,textarea,select,button,[tabindex]');
if (!control) return JSON.stringify({state: 'not-focusable'});
control.focus({preventScroll: true});
return JSON.stringify({state: document.activeElement === control ? 'focused' : 'unfocused'});
}''';

const _pointerProbe =
    '''
function() {
$_elementPrelude
const r = el.getBoundingClientRect();
const rect = {x:r.x, y:r.y, width:r.width, height:r.height};
const style = getComputedStyle(el);
if (r.width <= 0 || r.height <= 0 || style.display === 'none' ||
    style.visibility === 'hidden') return JSON.stringify({...rect,state:'hidden'});
const x = r.x+r.width/2, y = r.y+r.height/2;
const hit = document.elementFromPoint(x,y);
const root = el.getRootNode();
const pane = el.closest('flt-glass-pane') ||
  (root.host && (root.host.matches('flt-glass-pane') ? root.host : root.host.closest('flt-glass-pane')));
const view = el.closest('flutter-view') || (root.host && root.host.closest('flutter-view'));
const proxy = el.closest('flt-semantics');
// Flutter may put an empty structural semantics receiver over its canvas.
// It forwards raw input to the framework; it is not another actionable control.
const structuralReceiver = hit && hit.matches('flt-semantics') &&
  !hit.hasAttribute('flt-tappable') && !hit.hasAttribute('role') &&
  !hit.getAttribute('aria-label') && !(hit.textContent || '').trim();
const sameOwner = hit && ((pane && hit.closest('flt-glass-pane') === pane) ||
  (view && hit.closest('flutter-view') === view));
const sameFlutterSurface = !!(proxy && sameOwner &&
  (hit.matches('canvas,flt-scene-host,flt-glass-pane') || hit.closest('flt-scene-host') || structuralReceiver));
const hitOk = !!(hit && (hit === el || el.contains(hit) || sameFlutterSurface));
return JSON.stringify({...rect,flutterProxy:!!proxy,state:hitOk?'ready':'occluded'});
}''';

String _liveTargetProbe(SemanticTarget target, {required bool focus}) {
  final selectors = jsonEncode(
    [...target.scope, target].map((s) => s.toJson()).toList(),
  );
  final body = focus ? _focusProbe : _pointerProbe;
  return """
JSON.stringify((() => {
  const selectors = $selectors;
  let parent = document;
  let found;
  const role = e => e.getAttribute('role') ||
    ({BUTTON:'button',TEXTAREA:'textbox',SELECT:'combobox',A:'link'})[e.tagName] ||
    (e.tagName === 'INPUT' ? (e.type === 'range' ? 'slider' :
      e.type === 'checkbox' ? 'checkbox' : 'textbox') : 'generic');
  const label = e => e.getAttribute('aria-label') || e.textContent || '';
  for (const s of selectors) {
    const candidates = [...parent.querySelectorAll(
      'flt-semantics,[aria-label],[role],button,input,textarea,select,a')];
    const matches = candidates.filter(e => (!s.role || role(e) === s.role) &&
      (!s.name || label(e) === s.name));
    if (matches.length !== 1) {
      return {state:matches.length?'ambiguous':'missing',count:matches.length};
    }
    found=matches[0];
    parent=found;
  }
  return JSON.parse(($body).call(found));
})())
""";
}
