/* This handler reads only the selection associated with a real context menu. */
(() => {
    "use strict";
    const plainInputTypes = new Set(["text", "search", "email", "url", "tel"]);

    function selectedText(event) {
        const target = event.composedPath?.()[0] || event.target;
        // Never reuse a document selection when right-clicking a password field.
        if (target instanceof HTMLInputElement && target.type === "password") return "";
        const isTextInput = target instanceof HTMLTextAreaElement ||
            (target instanceof HTMLInputElement && plainInputTypes.has(target.type));
        if (isTextInput) {
            try {
                if (Number.isInteger(target.selectionStart) && Number.isInteger(target.selectionEnd)) {
                    return target.value.slice(target.selectionStart, target.selectionEnd);
                }
            } catch (_) { return ""; }
        }
        return window.getSelection()?.toString() || "";
    }

    document.addEventListener("contextmenu", event => {
        if (!event.isTrusted) return;
        const text = selectedText(event).trim();
        // A conservative UTF-16 cap here bounds IPC; Swift applies the grapheme cap.
        const selected = Array.from(text).slice(0, 8000).join("");
        safari.extension.setContextMenuEventUserInfo(event, { selectedText: selected });
    }, true);
})();
