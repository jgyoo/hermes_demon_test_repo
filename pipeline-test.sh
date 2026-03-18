#!/bin/bash
# Olympus v2 — E2E Pipeline Test Script
#
# 사용법:
#   curl -sL https://raw.githubusercontent.com/jgyoo/hermes_demon_test_repo/main/pipeline-test.sh | bash
#
# 환경 변수:
#   OLYMPUS_URL — Olympus API URL (기본: Railway 주소)

set -e

URL="${OLYMPUS_URL:-https://olympus-production-3544.up.railway.app}"

api() {
  curl -s -X POST "$URL/api/request" \
    -H "Content-Type: application/json" \
    -d "$1"
}

get() {
  curl -s "$URL/api$1"
}

echo "╔══════════════════════════════════════════╗"
echo "║   🏛️  Olympus v2 — Pipeline Test         ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  URL: $URL"
echo ""

# ── Step 0: Health Check ──
echo "━━━ Step 0: Health Check ━━━"
HEALTH=$(get "/health")
echo "$HEALTH" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  Platform: {d.get(\"platform\")}')
for m in d.get('modules', []):
    det = m.get('details', {})
    print(f'  {m[\"module\"]:10} {m[\"state\"]:10} {det}')
for dm in d.get('daemons', []):
    print(f'  daemon: {dm[\"name\"]} state={dm[\"state\"]}')
" 2>/dev/null
echo ""

# ── Step 1: Reset Dedup Cache ──
echo "━━━ Step 1: Dedup 캐시 초기화 ━━━"
RESET=$(api '{"type":"iris.reset_dedup","source":"pipeline-test","payload":{"adapter":"slack"}}')
echo "  Slack: $(echo $RESET | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r.get("result",{}).get("message","failed"))' 2>/dev/null)"

RESET2=$(api '{"type":"iris.reset_dedup","source":"pipeline-test","payload":{"adapter":""}}')
echo "  전체: $(echo $RESET2 | python3 -c 'import sys,json; r=json.load(sys.stdin); print(r.get("result",{}).get("message","failed"))' 2>/dev/null)"
echo ""

# ── Step 2: Send Test Meeting to Slack ──
echo "━━━ Step 2: Slack 테스트 미팅 메시지 전송 ━━━"
NOTIFY=$(api '{
  "type": "iris.notify",
  "source": "pipeline-test",
  "payload": {
    "channel": "slack",
    "body": "=== 파이프라인 E2E 테스트 ('$(date +%H:%M)') ===\n\n주요 논의:\n• Olympus v2 온톨로지 팔란티어 모델 전환 완료\n• DB 레지스트리 (프롬프트/스킬/규칙) 구현\n• 프로덕션 UX 개선 — Approvals 500, Mnemo 무한루프 수정\n\n결정사항:\n• 파일 기반 → DB 기반으로 전면 전환\n• LLM이 프롬프트를 자가 개선 가능한 구조\n• 온톨로지 ObjectType/Property/LinkType 세 가지만 존재\n\n다음 단계:\n• 텔레메트리 수집 확인\n• 데몬 업데이트 자동화"
  }
}')
NOTIFY_STATUS=$(echo $NOTIFY | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status","?"))' 2>/dev/null)
echo "  Notify: $NOTIFY_STATUS"
echo ""

# ── Step 3: Wait & Collect ──
echo "━━━ Step 3: Slack 수집 (3초 대기 후) ━━━"
sleep 3

COLLECT=$(api '{"type":"iris.collect","source":"pipeline-test","payload":{"adapter":"slack"}}')
COLLECTED=$(echo $COLLECT | python3 -c 'import sys,json; r=json.load(sys.stdin).get("result",{}); print(f"collected={r.get(\"collected\",0)} archived={r.get(\"archived\",0)}")' 2>/dev/null)
echo "  $COLLECTED"
echo ""

# ── Step 4: Check Archives ──
echo "━━━ Step 4: 아카이브 확인 ━━━"
ARCHIVES=$(get "/mnemo/archives?limit=5")
echo "$ARCHIVES" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for a in d.get('archives', [])[:5]:
    meta = a.get('metadata', {})
    if isinstance(meta, str):
        meta = json.loads(meta) if meta else {}
    st = meta.get('source_type', '?')
    print(f'  {a[\"collector\"]:10} {st:15} {a[\"source_id\"][:50]}')
" 2>/dev/null
echo ""

# ── Step 5: Check Activity Log ──
echo "━━━ Step 5: 최근 활동 로그 ━━━"
ACTIVITY=$(get "/activity?limit=10")
echo "$ACTIVITY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for e in d.get('entries', [])[:10]:
    det = e.get('details', {})
    msg = det.get('message', e.get('activity', ''))[:60] if det else e.get('activity', '')[:60]
    print(f'  {e[\"timestamp\"][:19]} | {e.get(\"source\",\"?\"):25} | {msg}')
" 2>/dev/null
echo ""

# ── Step 6: Check Athena Results ──
echo "━━━ Step 6: Athena 분석 결과 ━━━"
RESULTS=$(get "/athena/brain/results?limit=5")
echo "$RESULTS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
results = d.get('results', [])
if not results:
    print('  (아직 분석 결과 없음)')
for r in results[:5]:
    print(f'  {r[\"status\"]:10} mode={r.get(\"mode\",\"?\"):6} actions={r.get(\"action_count\",0)} | {r[\"input\"][:50]}')
" 2>/dev/null
echo ""

# ── Step 7: Check Hermes Tasks ──
echo "━━━ Step 7: Hermes 태스크 ━━━"
HERMES=$(api '{"type":"hermes.daemons","source":"pipeline-test"}')
echo "$HERMES" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('result', {})
daemons = d.get('daemons', [])
for dm in daemons:
    print(f'  {dm[\"name\"]:20} {dm[\"status\"]:10} hb={dm.get(\"last_heartbeat\",\"?\")[:19]}')
print(f'  Total daemons: {d.get(\"count\",0)}')
" 2>/dev/null
echo ""

# ── Step 8: Check Ontology ──
echo "━━━ Step 8: 온톨로지 상태 ━━━"
get "/mnemo/ontology/status" 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  Object Types: {d.get(\"type_count\",\"?\")}, Link Types: {d.get(\"link_type_count\",\"?\")}')
" 2>/dev/null || echo "  (온톨로지 API 미배포)"
echo ""

# ── Step 9: Check Flows ──
echo "━━━ Step 9: Flow Tracer ━━━"
FLOWS=$(get "/flows")
echo "$FLOWS" | python3 -c "
import sys, json
d = json.load(sys.stdin)
flows = d.get('flows') or []
if not flows:
    print('  (활성 플로우 없음)')
for f in flows[:5]:
    print(f'  {f.get(\"id\",\"?\")[:20]} status={f.get(\"status\",\"?\")} nodes={len(f.get(\"nodes\",[]))}')
" 2>/dev/null
echo ""

echo "━━━ 테스트 완료 ━━━"
echo ""
echo "📊 콘솔에서 확인:"
echo "  $URL/apps/cck-internal/dashboard"
echo "  $URL/apps/cck-internal/knowledge"
echo "  $URL/apps/cck-internal/athena"
echo "  $URL/apps/cck-internal/activity"
