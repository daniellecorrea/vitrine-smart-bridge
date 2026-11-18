#!/usr/bin/env bash
# Ponte de publicação no GitHub Actions.
#
# Modo padrão (BRIDGE_WA=0): roda SÓ o app de publicação. O gateway Baileys
# continua onde está (PC/Render) — dois clientes na mesma sessão brigam pelo
# pareamento e derrubam o WhatsApp. Só ligue BRIDGE_WA=1 quando o gateway
# local estiver parado de propósito.
set -u
export PYTHONUNBUFFERED=1
mkdir -p runtime
APP_PID=""
GW_PID=""
BRIDGE_WA="${BRIDGE_WA:-0}"

# Fim do run (ou cancelamento) precisa fechar o app com SIGTERM: o lifespan
# devolve a conexão do advisory lock ao pooler. Sem isso a sessão do runner
# morto pode segurar o lock e o run seguinte fica HTTP-only (o app tem uma
# rede de segurança de 10 min, mas o shutdown limpo evita a espera).
cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) encerrando app (pid $APP_PID)"
    kill -TERM "$APP_PID" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$APP_PID" 2>/dev/null || break
      sleep 1
    done
  fi
}
trap cleanup EXIT TERM INT

start_app() {
  python bridge_app.py >> runtime/app.log 2>&1 &
  APP_PID=$!
  echo "app pid=$APP_PID"
}

start_gw() {
  (
    cd app/wa-gateway || exit 1
    node --env-file="$(pwd)/../../runtime/gateway.env" baileys-server.js \
      >> "$(pwd)/../../runtime/gateway.log" 2>&1
  ) &
  GW_PID=$!
  echo "gateway pid=$GW_PID"
}

show() {
  echo "== app (ultimas linhas) =="
  tail -n 20 runtime/app.log 2>/dev/null || echo "(sem log do app)"
  if [ "$BRIDGE_WA" = "1" ]; then
    echo "== gateway (ultimas linhas) =="
    tail -n 25 runtime/gateway.log 2>/dev/null || echo "(sem log do gateway)"
  fi
}

echo "modo da ponte: $([ "$BRIDGE_WA" = "1" ] && echo 'app + gateway' || echo 'somente app (gateway local intocado)')"
start_app
[ "$BRIDGE_WA" = "1" ] && start_gw

# Espera o app subir (max 150s) em vez de dormir cego.
for i in $(seq 1 30); do
  sleep 5
  if curl -sf -m 5 http://127.0.0.1:8010/health -o /dev/null 2>/dev/null; then
    echo "app pronto em $((i * 5))s"
    break
  fi
done

echo "== health inicial =="
curl -s -m 20 http://127.0.0.1:8010/health | head -c 900 || true
echo
if [ "$BRIDGE_WA" = "1" ]; then
  echo -n "gateway: "
  curl -s -m 10 http://127.0.0.1:8080/health || true
  echo
fi

# Cobertura: registra quanto tempo este run promete cobrir. O app le esse
# heartbeat e alerta ANTES de a janela vencer ou se o runner morrer no meio.
echo "== heartbeat da ponte =="
python app/scripts/ops_forecast.py --env-file runtime/app.env --heartbeat-start \
  || echo "heartbeat inicial falhou (a ponte segue; previsao fica sem cobertura)"

if [ "$BRIDGE_WA" = "1" ]; then
  echo "== validacao da sessao =="
  sleep 60
  show
fi

if [ -n "${TEST_CHANNEL:-}" ]; then
  echo "== teste manual em $TEST_CHANNEL (item $TEST_ITEM) =="
  python - <<PY
import time, urllib.request
token = ""
for raw in open("runtime/app.env", encoding="utf-8", errors="ignore"):
    if raw.startswith("DASHBOARD_TOKEN="):
        token = raw.split("=", 1)[1].strip()
url = "http://127.0.0.1:8010/api/publish/items?item_ids=${TEST_ITEM}&channel=${TEST_CHANNEL}"
for i in range(10):
    try:
        req = urllib.request.Request(url, method="POST", headers={"X-Dashboard-Token": token})
        print(urllib.request.urlopen(req, timeout=180).read().decode()[:400])
        break
    except Exception as exc:
        print("teste", i, type(exc).__name__, str(exc)[:140])
        time.sleep(15)
PY
fi

# Supervisao: 5h44, reinicia processo morto e mostra sinal de vida a cada 15 min.
for i in $(seq 1 344); do
  sleep 60
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) app morreu - reiniciando"
    start_app
  fi
  if [ "$BRIDGE_WA" = "1" ] && ! kill -0 "$GW_PID" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) gateway morreu - reiniciando"
    start_gw
  fi
  if [ $((i % 15)) -eq 0 ]; then
    python app/scripts/ops_forecast.py --env-file runtime/app.env --heartbeat-tick \
      >/dev/null 2>&1 || echo "$(date -u +%FT%TZ) heartbeat falhou"
    if [ "$BRIDGE_WA" = "1" ]; then
      echo -n "$(date -u +%FT%TZ) min=$i gateway="
      curl -s -m 10 http://127.0.0.1:8080/health || echo -n "sem-health"
      echo
    else
      echo -n "$(date -u +%FT%TZ) min=$i app="
      curl -s -m 10 http://127.0.0.1:8010/health | head -c 120 || echo -n "sem-health"
      echo
    fi
    tail -n 3 runtime/app.log 2>/dev/null
  fi
done

echo "fim da janela do runner"
show
