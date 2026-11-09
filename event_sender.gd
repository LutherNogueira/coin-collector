class_name EventSender
extends RefCounted
## Sends the events to the collection endpoint, in the browser only. The batching happens in a small piece of
## JavaScript that lives in the page, because only the page can still send when the tab is being closed: it
## flushes every few seconds, when 50 events pile up, and when the page is hidden or unloaded (navigator.sendBeacon).
## Delivery is best effort and never blocks the game; whatever is lost stays in the local log.
## The player can switch it off in the Esc menu, and nothing is sent outside the web build.

const ENDPOINT := "/api/ingest"

const JS := """
(function () {
  if (window.__coinIngest) return;
  var MAX_BATCH = 50, MAX_BUFFER = 500, EVERY_MS = 10000;
  var buffer = [];
  var api = { enabled: true, sent: 0, batches: 0, dropped: 0 };
  function flush() {
    while (buffer.length) {
      var lines = buffer.slice(0, MAX_BATCH);
      var body = '{"events":[' + lines.join(',') + ']}';
      var queued = false;
      try { queued = navigator.sendBeacon('%s', new Blob([body], { type: 'text/plain' })); } catch (e) {}
      if (!queued) break;   // keep them for the next flush
      buffer.splice(0, lines.length);
      api.sent += lines.length;
      api.batches += 1;
    }
    if (buffer.length > MAX_BUFFER) { api.dropped += buffer.length - MAX_BUFFER; buffer.splice(0, buffer.length - MAX_BUFFER); }
  }
  api.push = function (line) {
    if (!api.enabled) return;
    buffer.push(line);
    if (buffer.length >= MAX_BATCH) flush();
  };
  api.setEnabled = function (on) { api.enabled = !!on; if (!on) buffer.length = 0; };
  api.flush = flush;
  setInterval(flush, EVERY_MS);
  document.addEventListener('visibilitychange', function () { if (document.visibilityState === 'hidden') flush(); });
  window.addEventListener('pagehide', flush);
  window.__coinIngest = api;
})();
""" % ENDPOINT

var _api: JavaScriptObject = null


## True when this build can send at all (the web export).
static func is_available() -> bool:
	return OS.has_feature("web")


func start(enabled: bool) -> void:
	if not is_available():
		return
	JavaScriptBridge.eval(JS)
	_api = JavaScriptBridge.get_interface("__coinIngest")
	set_enabled(enabled)


func set_enabled(enabled: bool) -> void:
	if _api != null:
		_api.setEnabled(enabled)


## Takes one event line (already JSON); this is what the logger's `sink` calls.
func push(line: String) -> void:
	if _api != null:
		_api.push(line)
