# Ponte de publicação — Vitrine Smart

Este repositório é **só infraestrutura**: um workflow que roda o app de
publicação e o gateway de WhatsApp num runner do GitHub Actions. O código do
app continua **privado** em `daniellecorrea/vitrine-smart` e é clonado a cada
execução com um token guardado em secret.

Existe porque o Render está suspenso por cota até 01/12 e todos os provedores
alternativos de hospedagem gratuita exigem cartão. Repositório público =
minutos ilimitados no Actions, **sem cartão e sem custo**.

## Como funciona

1. `actions/checkout` clona este repo e depois o app privado (branch
   `claude/migracao-vercel-supabase`) usando o secret `PRIVATE_REPO_TOKEN`.
2. Instala `requirements.txt` (Python 3.13) e `wa-gateway` (Node 20).
3. Grava `runtime/app.env` e `runtime/gateway.env` a partir dos secrets
   `APP_ENV_B64` e `GATEWAY_ENV_B64` (base64, nunca em texto claro no repo).
4. `bridge.sh` sobe o app em `127.0.0.1:8010` e o gateway Baileys em
   `127.0.0.1:8080`, valida o health dos dois e fica de plantão por ~5h44,
   reiniciando qualquer processo que cair.
5. No runner o `PUBLIC_BASE_URL` fica vazio: o ngrok local não existe e o
   Instagram usa o CDN da Shopee direto.

## Cadência

- **Corrente de runs, sem cron**: o primeiro step de cada run enfileira o
  próximo via `workflow_dispatch` — o cron desta conta não dispara. A
  `concurrency: bridge` garante um run por vez; o seguinte espera na fila.
  Cada job cobre ~5h44, então a cobertura é praticamente contínua.
- `timeout-minutes: 355` é proposital: fica abaixo das 6h do Actions e acima
  da janela de supervisão.
- **Heartbeat de cobertura**: `bridge.sh` grava `--heartbeat-start` no
  início (com o fim previsto) e renova a cada 15 min. O app lê esse
  heartbeat e alerta **antes** de a janela vencer ou se o runner morrer.
  Sem heartbeat, a previsão mostra a ponte como ⚪; vencida ou em silêncio
  > 45 min vira 🔴 no privado da dona.

## Teste manual

Aba **Actions** → workflow **bridge** → **Run workflow**, informando:

- `test_channel`: `whatsapp` (ou `telegram`/`instagram`);
- `test_item`: id do produto na Shopee.

O teste usa `POST /api/publish/items` com o `DASHBOARD_TOKEN` do próprio
runner, furando janela de horário e intervalo. O resultado aparece no log
(`sent` / `skipped` / `failed`).

## O que NÃO fica aqui

- Código do app, banco, logs de produção.
- Qualquer credencial: tudo em **Settings → Secrets and variables → Actions**.
  Os três secrets existentes são `PRIVATE_REPO_TOKEN`, `APP_ENV_B64` e
  `GATEWAY_ENV_B64`.

## Avisos

- **Uma sessão por vez**: o gateway restaura a sessão Baileys do Supabase.
  Se o app/gateway local for ligado ao mesmo tempo, os dois clientes brigam
  pela sessão e o WhatsApp cai. Com a ponte ativa, o supervisor local deve
  ficar parado.
- **Workflow agendado em repo público** é desativado pelo GitHub após ~60
  dias sem atividade no repositório. A ponte é solução até 01/12; depois o
  Render volta e ela fica de reserva.
- Falha de run gera notificação padrão do GitHub para a dona da conta.
