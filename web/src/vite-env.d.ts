/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_EARNLINE_SYNC_ENDPOINT?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
