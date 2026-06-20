/* eslint-disable @next/next/no-img-element */
import { readFile } from "fs/promises";
import { join } from "path";
import { ImageResponse } from "next/og";

export const runtime = "nodejs";

const width = 1200;
const height = 630;

async function loadAsset(path: string) {
  const data = await readFile(join(process.cwd(), path));
  return `data:image/png;base64,${data.toString("base64")}`;
}

export async function GET() {
  const [instrumentSerifData, jetbrainsMonoData, appScreenshot] =
    await Promise.all([
      readFile(join(process.cwd(), "app/api/og/instrument-serif.woff")),
      readFile(join(process.cwd(), "app/api/og/jetbrains-mono.ttf")),
      loadAsset("public/macos-image.png"),
    ]);

  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        background: "#060606",
        color: "#f4f1eb",
        fontFamily: "JetBrains Mono",
        position: "relative",
        overflow: "hidden",
      }}
    >
      <div
        style={{
          position: "absolute",
          inset: 0,
          background:
            "linear-gradient(135deg, rgba(255,255,255,0.055) 0%, rgba(255,255,255,0.01) 34%, rgba(0,0,0,0) 68%)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 64,
          right: 64,
          top: 48,
          height: 1,
          background: "rgba(255,255,255,0.08)",
        }}
      />
      <div
        style={{
          position: "absolute",
          left: 64,
          right: 64,
          bottom: 48,
          height: 1,
          background: "rgba(255,255,255,0.06)",
        }}
      />

      <div
        style={{
          display: "flex",
          width: "100%",
          height: "100%",
          padding: "74px 68px",
          boxSizing: "border-box",
          position: "relative",
          gap: 44,
        }}
      >
        <div
          style={{
            width: 445,
            display: "flex",
            flexDirection: "column",
            justifyContent: "space-between",
            flexShrink: 0,
          }}
        >
          <div style={{ display: "flex", flexDirection: "column" }}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                color: "#7c766f",
                fontSize: 19,
                marginBottom: 46,
              }}
            >
              macOS beta
            </div>

            <div
              style={{
                fontFamily: "Instrument Serif",
                fontSize: 84,
                lineHeight: 0.98,
                color: "#f7f3ec",
                display: "flex",
                flexDirection: "column",
              }}
            >
              <span>hun in your</span>
              <span>menu bar.</span>
            </div>

            <div
              style={{
                marginTop: 26,
                color: "#9a938a",
                fontSize: 20,
                lineHeight: 1.55,
                display: "flex",
                flexDirection: "column",
              }}
            >
              <span>switch projects, watch logs,</span>
              <span>and control dev services without</span>
              <span>opening another terminal pane.</span>
            </div>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 12,
            }}
          >
            <div
              style={{
                display: "flex",
                alignItems: "center",
                alignSelf: "flex-start",
                border: "1px solid rgba(255,255,255,0.11)",
                borderRadius: 10,
                padding: "13px 16px",
                background: "rgba(255,255,255,0.055)",
                color: "#dfd8cc",
                fontSize: 17,
              }}
            >
              hun.sh/macos
            </div>
          </div>
        </div>

        <div
          style={{
            flex: 1,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            minWidth: 0,
          }}
        >
          <div
            style={{
              width: 620,
              height: 438,
              border: "1px solid rgba(255,255,255,0.14)",
              borderRadius: 18,
              overflow: "hidden",
              position: "relative",
              display: "flex",
              background: "#0a0a0a",
              boxShadow: "0 36px 90px rgba(0,0,0,0.5)",
            }}
          >
            <img
              alt=""
              src={appScreenshot}
              width="620"
              height="438"
              style={{
                width: "100%",
                height: "100%",
                objectFit: "cover",
              }}
            />
            <div
              style={{
                position: "absolute",
                inset: 0,
                border: "1px solid rgba(255,255,255,0.08)",
                borderRadius: 18,
              }}
            />
          </div>
        </div>
      </div>
    </div>,
    {
      width,
      height,
      fonts: [
        {
          name: "Instrument Serif",
          data: instrumentSerifData,
          style: "normal",
          weight: 400,
        },
        {
          name: "JetBrains Mono",
          data: jetbrainsMonoData,
          style: "normal",
          weight: 400,
        },
      ],
    },
  );
}
