FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libx11-6 libxrandr2 libxcursor1 libxinerama1 libxi6 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY build/server/cs-aim-server.x86_64 /app/server.x86_64
COPY build/server/cs-aim-server.pck /app/server.pck

RUN chmod +x /app/server.x86_64

EXPOSE 7777

ENV PORT=7777
CMD ["./server.x86_64", "--headless", "res://scenes/server.tscn"]
