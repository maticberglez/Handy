import { useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import UpdateChecker from "./UpdateChecker";
import { Button } from "../ui/Button";

interface UpdateStatus {
  available: boolean;
  running: boolean;
  success: boolean | null;
  log: string;
}

export default function CustomUpdate() {
  const { t } = useTranslation();
  const [status, setStatus] = useState<UpdateStatus | null>(null);
  const [visible, setVisible] = useState(false);
  const [error, setError] = useState("");
  const [starting, setStarting] = useState(false);
  const [copied, setCopied] = useState(false);
  const shownFailure = useRef<string | null>(null);

  useEffect(() => {
    let active = true;
    const refresh = async () => {
      try {
        const next = await invoke<UpdateStatus>("custom_update_status");
        if (active) {
          setStatus(next);
          if (
            next.success === false &&
            !next.running &&
            shownFailure.current !== next.log
          ) {
            shownFailure.current = next.log;
            setVisible(true);
          }
        }
      } catch (err) {
        if (active) setError(String(err));
      }
    };
    void refresh();
    const timer = setInterval(() => void refresh(), 1500);
    return () => {
      active = false;
      clearInterval(timer);
    };
  }, []);

  const start = async () => {
    shownFailure.current = null;
    setStarting(true);
    setError("");
    setCopied(false);
    try {
      await invoke("start_custom_update");
      setStatus(await invoke<UpdateStatus>("custom_update_status"));
    } catch (err) {
      setError(String(err));
    } finally {
      setStarting(false);
    }
  };

  if (status && !status.available) return <UpdateChecker />;
  const busy = starting || status?.running;
  const label = busy
    ? t("customUpdate.running")
    : status?.success === true
      ? t("customUpdate.success")
      : status?.success === false || error
        ? t("customUpdate.failed")
        : t("customUpdate.button");

  return (
    <>
      <Button variant="secondary" size="sm" onClick={() => setVisible(true)}>
        {label}
      </Button>
      {visible && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm">
          <section
            role="dialog"
            aria-modal="true"
            aria-labelledby="custom-update-title"
            className="bg-background border border-line rounded-2xl shadow-2xl p-6 w-full max-w-2xl mx-4 space-y-5 text-sm text-ink"
          >
            <h2
              id="custom-update-title"
              className="text-lg font-semibold tracking-tight"
            >
              {t("customUpdate.title")}
            </h2>
            <p className="text-ink-2 leading-relaxed">
              {t("customUpdate.description")}
            </p>
            <p
              role="status"
              className={`rounded-lg border px-3 py-2 font-medium ${
                error || status?.success === false
                  ? "border-error/30 bg-error-wash text-error"
                  : "border-line bg-wash"
              }`}
            >
              {label}
            </p>
            <pre className="max-h-72 overflow-auto whitespace-pre-wrap break-words text-xs leading-relaxed bg-wash border border-line p-4 rounded-lg select-text">
              {[error, status?.log].filter(Boolean).join("\n\n") ||
                t("customUpdate.ready")}
            </pre>
            <div className="flex flex-wrap gap-2 justify-end border-t border-line pt-4">
              <Button
                variant="secondary"
                onClick={async () => {
                  try {
                    await navigator.clipboard.writeText(
                      [error, status?.log].filter(Boolean).join("\n\n"),
                    );
                    setCopied(true);
                  } catch (err) {
                    setError(`${t("customUpdate.copyFailed")} ${String(err)}`);
                  }
                }}
                disabled={!error && !status?.log}
              >
                {copied ? t("customUpdate.copied") : t("customUpdate.copy")}
              </Button>
              <Button
                variant="primary"
                onClick={() => void start()}
                disabled={!!busy || !status?.available}
              >
                {t("customUpdate.button")}
              </Button>
              <Button variant="secondary" onClick={() => setVisible(false)}>
                {t("common.close")}
              </Button>
            </div>
          </section>
        </div>
      )}
    </>
  );
}
