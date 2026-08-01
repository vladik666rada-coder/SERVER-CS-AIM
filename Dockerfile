FROM godotengine/godot:4.7-server AS builder

WORKDIR /build
COPY . .

RUN godot --headless --path /build --export-release "Linux Server" /build/server/cs-aim-server.x86_64

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libx11-6 libxrandr2 libxcursor1 libxinerama1 libxi6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /build/server/cs-aim-server.x86_64 /app/server.x86_64
COPY --from=builder /build/server/cs-aim-server.pck /app/server.pck

EXPOSE 7777

ENV PORT=7777
CMD ["./server.x86_64", "--headless", "--path", "/app", "res://scenes/server.tscn"]
