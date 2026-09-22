import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import { defineConfig } from "vitest/config";

export default defineConfig({
  server: {
    proxy: {
      "/api": "http://localhost:8787"
    }
  },
  plugins: [
    react(),
    VitePWA({
      registerType: "autoUpdate",
      manifest: {
        name: "STTS",
        short_name: "STTS",
        description: "Voice-first agent conversations",
        theme_color: "#102a43",
        background_color: "#edf3f6",
        display: "standalone",
        orientation: "portrait-primary",
        start_url: "/",
        icons: [
          { src: "/pwa-192x192.png", sizes: "192x192", type: "image/png" },
          { src: "/pwa-512x512.png", sizes: "512x512", type: "image/png" },
          {
            src: "/pwa-512x512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable"
          }
        ]
      },
      pwaAssets: {
        image: "public/icon.svg"
      },
      workbox: {
        navigateFallback: "/index.html"
      }
    })
  ],
  test: {
    environment: "jsdom",
    setupFiles: "./src/test-setup.ts"
  }
});
