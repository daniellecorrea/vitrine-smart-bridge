# Ponte de publicação — Vitrine Smart

Este repositório é **só infraestrutura**: um workflow que roda o app de
publicação num runner do GitHub Actions. O código do app continua **privado**
em `daniellecorrea/vitrine-smart` e é clonado a cada execução com um token
guardado em secret.

O **gateway de WhatsApp não sobe aqui** por padrão. A sessão Baileys é única:
um segundo cliente na mesma sessão derruba o pareamento. Enquanto a dona
opera o gateway no PC, a ponte roda só o app (`BRIDGE_WA=0`).

Existe porque o Render está suspenso por cota até 01/12 e todos os provedores
alternativos de hospedagem gratuita exigem cartão. Repositório público =
minutos ilimitados no Actions, **sem cartão e sem custo**.

## Como funciona

1. `actions/checkout` clona este repo e depois o app privado (branch
   `claude/migracao-vercel-supabase`) usando o secret `PRIVATE_REPO_TOKEN`.
2. Instala `requirements.txt` (Python 3.13).
3. Grava `runtime/app.env` a partir do secret `APP_ENV_B64` (base64, nunca
   em texto claro no repo). `runtime/gateway.env` continua disponível para
   quando `BRIDGE_WA=1`.
4. `bridge.sh` sobe o app em `127.0.0.1:8010`, valida o health e fica de
   plantão por ~5h44, reiniciando o app se ele cair.
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

- `test_channel`: `telegram` ou `instagram` (WhatsApp fica fora da ponte);
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

- **Uma sessão de WhatsApp por vez**: a sessão Baileys é única. Por isso a
  ponte sobe com `BRIDGE_WA=0` e não toca no gateway. Só use `BRIDGE_WA=1`
  com o gateway local **parado de propósito** — nunca com os dois ligados.
- **Handoff do app**: quando a ponte assume, o app local precisa ficar
  parado (o lock do agendador impede post duplicado, mas a máquina volta a
  ser dependência). O supervisor lê `_runtime/bridge_mode.txt`: com o
  arquivo presente, ele monitora só gateway/QR e não reinicia o app.
  Para voltar ao PC: apague o arquivo e suba o app de novo.
- **Workflow agendado em repo público** é desativado pelo GitHub após ~60
  dias sem atividade no repositório. A ponte é solução até 01/12; depois o
  Render volta e ela fica de reserva.
- Falha de run gera notificação padrão do GitHub para a dona da conta.
