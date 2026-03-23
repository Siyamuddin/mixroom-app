# Producer Data Collection SOP (EN/KR)

This document is the handoff guide for producers who create training data for Mixroom's AI mixing model.  
이 문서는 Mixroom AI 믹싱 모델 학습 데이터를 제작하는 프로듀서를 위한 작업 가이드입니다.

---

## 1) Objective / 목표

**EN**  
Your job is to make the AI's result sound release-ready by applying expert corrections after AI actions.  
Each correction teaches the model how much change is actually needed in real mix context.

**KR**  
당신의 역할은 AI가 적용한 결과를 기준으로, 전문가 보정을 통해 릴리즈 가능한 사운드로 만드는 것입니다.  
각 보정은 실제 믹스 맥락에서 “얼마나” 조정해야 하는지를 모델에 학습시킵니다.

---

## 2) Core Principle / 핵심 원칙

**EN**  
Always let AI act first, then correct.  
Do not pre-mix everything manually before giving prompts.

**KR**  
항상 **AI가 먼저 적용**하도록 한 뒤 보정하세요.  
프롬프트 전, 수동으로 전체를 미리 다 믹스하지 마세요.

---

## 3) Session Workflow / 세션 작업 순서

### Step A. Start session / 세션 시작
**EN**
1. Open one project/song.
2. Turn on **Producer Capture** (UI toggle) or type `/producer on`.
3. Confirm assistant says capture is enabled.

**KR**
1. 프로젝트/곡 하나를 엽니다.
2. **Producer Capture**를 켜거나 `/producer on`을 입력합니다.
3. 캡처가 활성화되었다는 안내 메시지를 확인합니다.

### Step B. Run one prompt cycle / 프롬프트 1회 사이클
**EN**
1. Enter one realistic mix prompt.
2. Let AI apply changes.
3. Listen.
4. Correct only what is needed.
5. Press **Capture Final** when result is at professional quality (you would ship it).

**KR**
1. 현실적인 믹스 프롬프트 1개를 입력합니다.
2. AI가 변경을 적용하게 둡니다.
3. 들어봅니다.
4. 필요한 부분만 보정합니다.
5. 본인이 릴리즈 가능하다고 판단되는 품질에서 **Capture Final**을 누릅니다.

### Step C. Repeat / 반복
**EN**  
Repeat Step B with different prompts on the same project, then move to another project.

**KR**  
같은 프로젝트에서 다양한 프롬프트로 Step B를 반복한 뒤, 다음 프로젝트로 넘어갑니다.

### Step D. Export / 내보내기
**EN**
1. Export with UI **Export** button or `/producer export`.
2. Keep the exported `.json` file path.
3. At end of day, send all exported session `.json` files.
Note: Export also auto-finalizes the current prompt cycle if you forgot to press **Capture Final**.

**KR**
1. UI의 **Export** 버튼 또는 `/producer export`로 내보냅니다.
2. 출력된 `.json` 파일 경로를 보관합니다.
3. 작업 종료 시 세션 `.json` 파일들을 모두 전달합니다.
참고: **Capture Final**을 누르지 않았더라도 Export 시 현재 프롬프트 사이클은 자동으로 종료 표시됩니다.

### Step E. Close / 종료
**EN**  
Turn off capture with UI toggle or `/producer off` before leaving the project.

**KR**  
프로젝트를 닫기 전에 UI 토글 또는 `/producer off`로 캡처를 종료합니다.

---

## 4) Prompt Quality Rules / 프롬프트 품질 규칙

**EN**
- Use natural user-style requests (not technical parameter language).
- Include both broad goals and targeted asks.
- Include subtle and aggressive requests.
- Include occasional “no change needed” cases.

**KR**
- 파라미터 언어보다 실제 사용자 말투의 요청을 사용하세요.
- 전체 목표형 요청과 특정 대상 요청을 모두 포함하세요.
- 약한/강한 요청을 모두 포함하세요.
- 가끔은 “변경 불필요” 사례도 포함하세요.

---

## 5) Editing Rules / 보정 작업 규칙

**EN**
- Correct over-processing and under-processing.
- Make intentional edits only; avoid random tweaking.
- If AI result is already correct, leave it.
- Avoid changing unrelated tracks just to “touch everything.”

**KR**
- 과도 처리/부족 처리를 모두 바로잡으세요.
- 의도 있는 수정만 하세요. 랜덤 트윅은 금지합니다.
- AI 결과가 이미 맞으면 그대로 두세요.
- “전체를 건드리기 위해” 무관 트랙을 수정하지 마세요.

---

## 6) Coverage Targets / 데이터 커버리지 목표

**EN**
- Genre diversity: pop, rock, hip-hop, EDM, acoustic, etc.
- Source diversity: clean stems + rough/problematic recordings.
- Arrangement diversity: sparse and dense mixes.
- Action diversity: gain/pan/EQ/compressor/reverb/delay/de-esser/distortion/limiter/clipper.

**KR**
- 장르 다양성: pop, rock, hip-hop, EDM, acoustic 등.
- 소스 다양성: 깨끗한 스템 + 거친/문제 있는 녹음.
- 편성 다양성: 트랙이 적은 믹스와 많은 믹스 모두.
- 액션 다양성: gain/pan/EQ/compressor/reverb/delay/de-esser/distortion/limiter/clipper.

---

## 7) Example Prompt Cycle / 예시 프롬프트 사이클

### Example (EN)
**Project**: Pop track with vocal, drums, bass, synth.  
**Prompt**: “Make vocals sit forward but still natural.”  
**AI applies**: Vocal gain up, presence EQ boost, light compression.  
**Your correction**:
1. Reduce vocal gain slightly (AI pushed too far).
2. Keep compression.
3. Lower high EQ boost a bit to remove sharpness.
4. Add very small de-esser threshold reduction only if needed.
**Stop condition**: Vocal is clearly in front, not harsh, blend remains musical.

### 예시 (KR)
**프로젝트**: 보컬/드럼/베이스/신스가 있는 팝 트랙  
**프롬프트**: “보컬이 앞으로 오되 자연스럽게 들리게 해줘.”  
**AI 적용**: 보컬 게인 상승, 프레즌스 EQ 부스트, 약한 컴프레션  
**당신의 보정**:
1. 보컬 게인을 소폭 낮춤 (AI가 과하게 올림).
2. 컴프레션은 유지.
3. 고역 EQ 부스트를 조금 낮춰 날카로움 제거.
4. 필요할 때만 디에서 임계값을 아주 소폭 조정.
**종료 기준**: 보컬이 충분히 전면에 있으면서 거칠지 않고, 전체 밸런스가 음악적으로 자연스러움.

---

## 8) Daily Handoff Package / 일일 전달 패키지

**EN**
Send:
1. All exported session `.json` files.
2. A short note: genres covered, rough hours worked, any unusual issues.
3. Optional quality note per session (1-2 lines).

**KR**
다음을 전달하세요:
1. Export된 세션 `.json` 파일 전체.
2. 짧은 메모: 작업 장르, 작업 시간(대략), 특이 이슈.
3. 선택 사항: 세션별 품질 메모(1~2줄).

---

## 9) Quick Do / Don't / 빠른 체크리스트

**EN - Do**
- Let AI act first.
- Make minimal necessary corrections.
- Press **Capture Final** once the prompt cycle is done.
- Keep decisions consistent and intentional.
- Export frequently.

**EN - Don't**
- Pre-mix before prompting.
- Over-edit everything.
- Rush through prompts without listening.

**KR - Do**
- AI를 먼저 적용시키세요.
- 필요한 최소 보정만 하세요.
- 일관되고 의도적인 판단을 유지하세요.
- 자주 Export 하세요.

**KR - Don't**
- 프롬프트 전에 미리 전부 수동 믹스하지 마세요.
- 모든 것을 과하게 수정하지 마세요.
- 충분히 듣지 않고 빠르게만 진행하지 마세요.
