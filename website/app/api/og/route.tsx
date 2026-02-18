import { ImageResponse } from "next/og";
import { readFile } from "fs/promises";
import { join } from "path";

export const runtime = "nodejs";

const BASE_WIDTH = 1200;
const BASE_HEIGHT = 630;
const MAX_DIMENSION = 4096;

function clamp(value: number, min: number, max: number) {
  return Math.min(max, Math.max(min, value));
}

function parsePositiveInt(value: string | null) {
  if (!value) return null;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

function parsePositiveFloat(value: string | null) {
  if (!value) return null;
  const parsed = Number.parseFloat(value);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

function resolveSize(url: URL) {
  const w = parsePositiveInt(url.searchParams.get("w"));
  const h = parsePositiveInt(url.searchParams.get("h"));
  const scale = parsePositiveFloat(url.searchParams.get("scale"));

  let width = BASE_WIDTH;
  let height = BASE_HEIGHT;

  if (w && h) {
    width = w;
    height = h;
  } else if (w) {
    width = w;
    height = Math.round((w * BASE_HEIGHT) / BASE_WIDTH);
  } else if (h) {
    height = h;
    width = Math.round((h * BASE_WIDTH) / BASE_HEIGHT);
  } else if (scale) {
    width = Math.round(BASE_WIDTH * scale);
    height = Math.round(BASE_HEIGHT * scale);
  }

  return {
    width: clamp(width, 200, MAX_DIMENSION),
    height: clamp(height, 200, MAX_DIMENSION),
  };
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const { width, height } = resolveSize(url);
  const title = url.searchParams.get("title") || "Documentation";
  const description = url.searchParams.get("description");
  const type = url.searchParams.get("type") || "home";

  const renderScale = Math.min(width / BASE_WIDTH, height / BASE_HEIGHT);
  const [instrumentSerifData, jetbrainsMonoData] = await Promise.all([
    readFile(join(process.cwd(), "app/api/og/instrument-serif.woff")),
    readFile(join(process.cwd(), "app/api/og/jetbrains-mono.ttf")),
  ]);

  if (type === "docs") {
    return new ImageResponse(
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          backgroundColor: "#0a0a0a",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        <div
          style={{
            width: `${BASE_WIDTH}px`,
            height: `${BASE_HEIGHT}px`,
            display: "flex",
            flexDirection: "column",
            backgroundColor: "#0a0a0a",
            position: "relative",
            overflow: "hidden",
            fontFamily: "JetBrains Mono",
            transform: `scale(${renderScale})`,
            transformOrigin: "center center",
            flexShrink: 0,
            boxSizing: "border-box",
            padding: "80px",
          }}
        >
          {/* Subtle background gradient/glow */}
          <div
            style={{
              position: "absolute",
              top: "-200px",
              right: "-200px",
              width: "600px",
              height: "600px",
              background: "radial-gradient(circle, rgba(255,255,255,0.03) 0%, rgba(0,0,0,0) 70%)",
              borderRadius: "50%",
            }}
          />

          {/* Border */}
          <div
            style={{
              position: "absolute",
              inset: "40px",
              border: "1px solid rgba(255,255,255,0.08)",
              borderRadius: "24px",
            }}
          />

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              height: "100%",
              zIndex: 10,
            }}
          >
            <div style={{ display: "flex", flexDirection: "column" }}>
              <div
                style={{
                  fontFamily: "Instrument Serif",
                  fontSize: 84,
                  color: "#f5f3ef",
                  lineHeight: 1.1,
                  letterSpacing: "-0.02em",
                  marginBottom: 24,
                  maxWidth: "900px",
                }}
              >
                {title}
              </div>

              {description && (
                <div
                  style={{
                    fontSize: 28,
                    color: "#a79f92",
                    lineHeight: 1.5,
                    maxWidth: "800px",
                    fontFamily: "JetBrains Mono",
                  }}
                >
                  {description}
                </div>
              )}
            </div>

            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                fontSize: 20,
                color: "#5c5750",
                fontFamily: "JetBrains Mono",
                borderTop: "1px solid rgba(255,255,255,0.08)",
                paddingTop: 32,
              }}
            >
              <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                <img
                  src="https://hun.sh/favicon.svg"
                  width="32"
                  height="32"
                  style={{ opacity: 0.8 }}
                />
                <span style={{ color: "#d0c8bc" }}>hun.sh</span>
                <span>/</span>
                <span>docs</span>
              </div>

              <div>
                seamless project context switching
              </div>
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
      }
    );
  }

  return new ImageResponse(
    <div
      style={{
        width: "100%",
        height: "100%",
        display: "flex",
        alignItems: "flex-start",
        justifyContent: "flex-start",
        backgroundColor: "#0a0a0a",
      }}
    >
      <div
        style={{
          width: `${BASE_WIDTH}px`,
          height: `${BASE_HEIGHT}px`,
          display: "flex",
          flexDirection: "column",
          backgroundColor: "#0a0a0a",
          position: "relative",
          overflow: "hidden",
          fontFamily: "JetBrains Mono",
          transform: `scale(${renderScale})`,
          transformOrigin: "top left",
          flexShrink: 0,
          boxSizing: "border-box",
        }}
      >
        <div
          style={{
            position: "absolute",
            width: "520px",
            height: "520px",
            border: "1px solid rgba(187, 164, 122, 0.14)",
            borderRadius: "999px",
            top: "-240px",
            right: "-110px",
          }}
        />
        <div
          style={{
            position: "absolute",
            width: "700px",
            height: "700px",
            border: "1px solid rgba(124, 144, 170, 0.1)",
            borderRadius: "999px",
            bottom: "-390px",
            left: "360px",
          }}
        />

        {/* top border line */}
        <div
          style={{
            position: "absolute",
            top: 0,
            left: "80px",
            right: "80px",
            height: "1px",
            backgroundColor: "rgba(255,255,255,0.06)",
          }}
        />

        {/* main content */}
        <div
          style={{
            display: "flex",
            alignItems: "stretch",
            justifyContent: "space-between",
            flex: 1,
            padding: "74px 84px",
            position: "relative",
          }}
        >
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              justifyContent: "center",
              maxWidth: "610px",
              fontFamily: "JetBrains Mono",
            }}
          >
            {/* hun.sh in Instrument Serif */}
            <div
              style={{
                fontFamily: "Instrument Serif",
                fontSize: 90,
                color: "#f5f3ef",
                lineHeight: 1,
                marginBottom: 30,
                letterSpacing: "-0.02em",
              }}
            >
              hun.sh
            </div>

            {/* tagline in monospace */}
            <div
              style={{
                fontSize: 20,
                color: "#b9b4aa",
                lineHeight: 1.45,
                display: "flex",
                flexDirection: "column",
                fontFamily: "JetBrains Mono",
              }}
            >
              <span>seamless project context</span>
              <span>switching for developers</span>
            </div>

            {/* brew command */}
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                marginTop: 42,
                fontSize: 17,
                border: "1px solid rgba(255,255,255,0.11)",
                borderRadius: "10px",
                padding: "12px 16px",
                alignSelf: "flex-start",
                background: "rgba(8, 8, 8, 0.62)",
                fontFamily: "JetBrains Mono",
              }}
            >
              <span style={{ color: "#9b9488" }}>$</span>
              <span style={{ color: "#e0d8cb" }}>brew install hun</span>
            </div>

            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                marginTop: 16,
                fontSize: 12,
                color: "#a79f92",
                fontFamily: "JetBrains Mono",
              }}
            >
              <span>focus mode</span>
              <span style={{ color: "#4f4b45" }}>•</span>
              <span>zero context drift</span>
            </div>
          </div>

          <div
            style={{
              width: "350px",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <div
              style={{
                width: "350px",
                height: "230px",
                border: "1px solid rgba(255,255,255,0.09)",
                borderRadius: "12px",
                backgroundColor: "rgba(14,14,14,0.88)",
                display: "flex",
                flexDirection: "column",
                overflow: "hidden",
                fontFamily: "JetBrains Mono",
              }}
            >
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "space-between",
                  padding: "10px 12px",
                  borderBottom: "1px solid rgba(255,255,255,0.07)",
                  fontSize: 11,
                  color: "#a59f93",
                  fontFamily: "JetBrains Mono",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 6,
                  }}
                >
                  <span style={{ color: "#6f4d4a" }}>●</span>
                  <span style={{ color: "#6d6552" }}>●</span>
                  <span style={{ color: "#4c6158" }}>●</span>
                </div>
                <span>hun status</span>
              </div>

              <div
                style={{
                  display: "flex",
                  flexDirection: "column",
                  gap: 8,
                  padding: "14px 14px 0 14px",
                  fontSize: 12,
                  fontFamily: "JetBrains Mono",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    color: "#d0c8bc",
                  }}
                >
                  <span>web</span>
                  <span>:5173 ✓</span>
                </div>
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    color: "#d0c8bc",
                  }}
                >
                  <span>api</span>
                  <span>:8000 ✓</span>
                </div>
                <div
                  style={{
                    display: "flex",
                    justifyContent: "space-between",
                    color: "#d0c8bc",
                  }}
                >
                  <span>agent</span>
                  <span>:8081 ✓</span>
                </div>
              </div>

              <div
                style={{
                  display: "flex",
                  flexDirection: "column",
                  gap: 7,
                  marginTop: 12,
                  padding: "0 14px",
                  fontSize: 11,
                  color: "#9c9488",
                  fontFamily: "JetBrains Mono",
                }}
              >
                <span>[ok] switched to voice-ai in 820ms</span>
                <span>[ok] logs streaming in realtime</span>
              </div>
            </div>
          </div>
        </div>

        {/* bottom border line */}
        <div
          style={{
            position: "absolute",
            bottom: 0,
            left: "80px",
            right: "80px",
            height: "1px",
            backgroundColor: "rgba(255,255,255,0.04)",
          }}
        />
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
