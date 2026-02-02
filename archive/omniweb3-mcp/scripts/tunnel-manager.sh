#!/bin/bash

TUNNEL_LOG="/tmp/omniweb3-tunnel.log"
TUNNEL_PID_FILE="/tmp/omniweb3-tunnel.pid"

case "$1" in
    start)
        if [ -f "$TUNNEL_PID_FILE" ]; then
            PID=$(cat "$TUNNEL_PID_FILE")
            if ps -p $PID > /dev/null 2>&1; then
                echo "❌ Tunnel is already running (PID: $PID)"
                echo ""
                grep "https://.*trycloudflare.com" "$TUNNEL_LOG" || echo "URL not found in log"
                exit 1
            fi
        fi

        echo "🌐 Starting cloudflared tunnel..."
        cloudflared tunnel --url http://127.0.0.1:8765 > "$TUNNEL_LOG" 2>&1 &
        TUNNEL_PID=$!
        echo $TUNNEL_PID > "$TUNNEL_PID_FILE"

        echo "⏳ Waiting for tunnel to initialize..."
        sleep 5

        echo ""
        echo "✅ Tunnel started!"
        echo ""
        URL=$(grep -oE "https://[^[:space:]]+" "$TUNNEL_LOG" | grep trycloudflare | head -1)
        if [ -n "$URL" ]; then
            echo "🔗 Your HTTPS URL:"
            echo "   $URL"
            echo ""
            echo "📋 Use this URL in Claude Desktop"
            echo "   PID: $TUNNEL_PID"
        else
            echo "⚠️  URL not ready yet. Check log:"
            echo "   tail -f $TUNNEL_LOG"
        fi
        ;;

    stop)
        if [ ! -f "$TUNNEL_PID_FILE" ]; then
            echo "❌ No tunnel PID file found"
            exit 1
        fi

        PID=$(cat "$TUNNEL_PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            echo "🛑 Stopping tunnel (PID: $PID)..."
            kill $PID
            rm "$TUNNEL_PID_FILE"
            echo "✅ Tunnel stopped"
        else
            echo "❌ Tunnel process not running"
            rm "$TUNNEL_PID_FILE"
        fi
        ;;

    status)
        if [ ! -f "$TUNNEL_PID_FILE" ]; then
            echo "❌ Tunnel is not running"
            exit 1
        fi

        PID=$(cat "$TUNNEL_PID_FILE")
        if ps -p $PID > /dev/null 2>&1; then
            echo "✅ Tunnel is running (PID: $PID)"
            echo ""
            URL=$(grep -oE "https://[^[:space:]]+" "$TUNNEL_LOG" | grep trycloudflare | head -1)
            if [ -n "$URL" ]; then
                echo "🔗 URL: $URL"
            fi
        else
            echo "❌ Tunnel PID file exists but process is not running"
            rm "$TUNNEL_PID_FILE"
        fi
        ;;

    restart)
        $0 stop
        sleep 2
        $0 start
        ;;

    *)
        echo "Usage: $0 {start|stop|status|restart}"
        echo ""
        echo "Commands:"
        echo "  start   - Start the cloudflared tunnel"
        echo "  stop    - Stop the tunnel"
        echo "  status  - Check tunnel status and show URL"
        echo "  restart - Restart the tunnel (new URL will be generated)"
        exit 1
        ;;
esac
