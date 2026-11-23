import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import { useTranslation } from "react-i18next";
import UpdateChecker from "./UpdateChecker";

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

  useEffect(() => {
    let active = true;
    const refresh = async () => {
      try {
        const next = await invoke<UpdateStatus>("custom_update_status");
        if (active) setStatus(next);
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
      <button className="hover:text-ink" onClick={() => setVisible(true)}>
        {label}
      </button>
      {visible && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
          <section
            role="dialog"
            aria-modal="true"
            aria-labelledby="custom-update-title"
            className="bg-background border border-line rounded-lg p-6 w-full max-w-2xl mx-4 space-y-4 text-sm text-ink"
          >
            <h2 id="custom-update-title" className="font-semibold">
              {t("customUpdate.title")}
            </h2>
            <p>{t("customUpdate.description")}</p>
            <p role="status">{label}</p>
            <pre className="max-h-72 overflow-auto whitespace-pre-wrap break-words text-xs bg-wash p-3 rounded select-text">
              {[error, status?.log].filter(Boolean).join("\n\n") ||
                t("customUpdate.ready")}
            </pre>
            <div className="flex gap-3 justify-end">
              <button
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
              </button>
              <button
                onClick={() => void start()}
                disabled={!!busy || !status?.available}
              >
                {t("customUpdate.button")}
              </button>
              <button onClick={() => setVisible(false)}>
                {t("common.close")}
              </button>
            </div>
          </section>
        </div>
      )}
    </>
  );
}
