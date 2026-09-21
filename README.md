# meeting-notes-kit

회의 녹음을 화자가 구분된 회의록으로 만드는 macOS 도구 모음입니다. 온라인 회의와 현장 회의를 각각 다른 경로로 처리하며, 회의 중에는 상대방의 영어 발언을 한국어 자막으로 볼 수 있습니다.

전사와 번역이 모두 로컬에서 돌기 때문에, 회의 내용이 외부로 나가지 않습니다.

```
meeting-notes/
├── bin/
│   ├── meeting          어느 폴더에서든 쓰는 진입점
│   ├── setup            최초 1회 설치
│   ├── prefetch         모델과 실시간 도구 미리 받기
│   ├── set-token        HuggingFace 토큰 넣기 (클립보드에서)
│   ├── setup-audio      시스템 오디오를 전사로 흘리는 장치 만들기
│   ├── live             실시간 자막 (전사 + 번역)
│   ├── translate        영어를 한국어로 (실시간 자막의 번역 단계)
│   ├── import-iphone    아이폰 녹음 가져오기
│   ├── transcribe       녹음을 화자별 회의록으로
│   ├── meeting_md.py    JSON을 화자별 마크다운으로 변환
│   └── selftest         스크립트를 고친 뒤 회귀 점검
├── examples/            결과물 예시
├── models/              실시간 전사용 whisper.cpp 모델 (git 추적 제외)
├── online/              01-inbox(원본) → 02-notes(회의록·자막)
└── offline/             01-inbox(녹음) → 02-transcripts(JSON) → 03-notes(회의록)
```

녹음 원본과 전사 결과, 완성된 회의록은 git으로 추적하지 않습니다. 회의록에는 실명과 내부 내용이 담기기 때문에 이 저장소에는 도구와 문서만 올라갑니다.

## 설치

### 준비물

| 항목 | 설명 |
| --- | --- |
| macOS | Core Audio와 음성 메모 연동을 쓰므로 macOS 전용입니다. |
| Apple Silicon | 필수는 아니지만, 실시간 전사가 Metal GPU를 쓰므로 M 계열에서 훨씬 빠릅니다. |
| [Homebrew](https://brew.sh) | 나머지 도구를 여기로 설치합니다. 없으면 먼저 설치해 주세요. |
| 디스크 여유 10GB | 전사 모델과 번역 모델을 합친 용량입니다. |

### 1. 내려받기

```bash
git clone https://github.com/YuchanJeong/meeting-notes-kit.git ~/meeting-notes
```

폴더 위치는 자유롭습니다. 진입점이 자기 위치를 기준으로 프로젝트를 찾습니다.

### 2. 기본 설치

```bash
cd ~/meeting-notes && bin/setup
```

여기서 설치되고 만들어지는 것은 이렇습니다.

| 무엇 | 왜 필요한지 |
| --- | --- |
| `uv` | whisperx를 격리된 환경에 설치하는 데 씁니다. |
| `ffmpeg` | 녹음 파일의 형식을 변환합니다. |
| `whisperx` | 사후 처리용 전사와 화자분리를 담당합니다. |
| `meeting` 명령 | `~/.local/bin/meeting`에서 이 폴더의 `bin/meeting`으로 이어집니다. |
| iCloud Drive/meeting-notes | 아이폰 음성 메모를 맥으로 넘기는 통로입니다. |
| `.env` | `.env.example`을 복사해서 만듭니다. |

`~/.local/bin`이 PATH에 없으면 `meeting` 명령을 찾지 못합니다. 설치 중에 안내가 나오며, 아래 한 줄을 `~/.zshrc`에 더하고 터미널을 새로 열면 됩니다.

```bash
export PATH="$HOME/.local/bin:$PATH"
```

### 3. HuggingFace 토큰

화자분리 모델이 게이트되어 있어서 세 단계를 모두 밟아야 합니다.

1. [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)에서 read 권한 토큰을 발급받아 복사한 뒤 `meeting set-token` 을 실행합니다. 클립보드에서 바로 읽어 `.env` 에 넣으므로 토큰이 화면이나 셸 기록에 남지 않습니다. 이미 넣어 둔 토큰을 확인만 하려면 `meeting set-token --check` 입니다.
2. [pyannote/speaker-diarization-3.1](https://huggingface.co/pyannote/speaker-diarization-3.1) 페이지에서 약관에 동의합니다.
3. [pyannote/segmentation-3.0](https://huggingface.co/pyannote/segmentation-3.0) 페이지에서도 동의합니다.

세 번째를 빠뜨리면 전사는 정상적으로 끝나는데 화자분리 단계에서 401 오류가 납니다.

### 4. 모델 미리 받기

```bash
meeting prefetch
```

사후 처리용 전사 모델과, 실시간 자막에 쓸 `whisper.cpp`, 번역용 Ollama 모델을 내려받습니다. 전부 합쳐 10GB 가까이 되고 회선에 따라 오래 걸리니, 자리를 비울 때 걸어 두는 편이 낫습니다. 각 단계는 실패해도 다음으로 넘어가며 끝에서 결과를 요약합니다.

화자분리 모델은 여기에 포함되지 않습니다. 토큰이 있어야 받을 수 있어서 첫 전사에서 자동으로 받습니다.

### 5. 실시간 자막을 쓴다면

상대방 목소리는 스피커로 나가기 때문에, 그 소리를 전사기로 함께 보내는 가상 장치가 필요합니다.

```bash
brew install blackhole-2ch
meeting setup-audio
```

`blackhole-2ch`는 시스템 오디오 드라이버라서 설치할 때 맥 비밀번호를 묻고, 설치 후 재부팅을 권하기도 합니다. `meeting setup-audio` 는 스피커와 BlackHole로 소리를 동시에 보내는 출력 장치를 만듭니다.

### 6. 온라인 회의 회의록을 만든다면

Anarlog가 마이크와 시스템 오디오를 동시에 잡아 전사와 요약까지 처리합니다.

```bash
brew install anarlog
```

설치되지 않으면 [anarlog.so/download](https://anarlog.so/download)에서 받습니다. 첫 실행 때 마이크와 화면 기록 권한을 모두 허용해야 합니다. 자세한 설정은 아래 online 항목에 있습니다.

### 설치가 끝났는지 확인하기

```bash
meeting                    쓸 수 있는 명령과 설명 보기
meeting set-token --check  토큰과 모델 접근 권한 확인
meeting selftest           스크립트 회귀 점검
```

## 명령 한눈에 보기

`meeting` 을 인자 없이 실행하면 아래 목록이 설명과 함께 나옵니다. 각 명령의 자세한 사용법은 `meeting <명령> --help` 로 볼 수 있습니다.

| 명령 | 하는 일 |
| --- | --- |
| `meeting setup` | 처음 한 번. 필요한 도구를 깔고 `.env` 를 만듭니다. |
| `meeting prefetch` | 전사와 번역에 쓸 모델을 미리 받아 둡니다. |
| `meeting set-token` | HuggingFace 토큰을 클립보드에서 `.env` 로 옮깁니다. |
| `meeting setup-audio` | 스피커와 BlackHole로 소리를 함께 보내는 장치를 만듭니다. |
| `meeting live` | 실시간 자막. 회의 중 상대방 말을 한국어로 봅니다. |
| `meeting translate` | 영어를 한국어로 옮깁니다. `live` 의 번역 단계이며 따로도 씁니다. |
| `meeting import-iphone` | 아이폰 음성 메모를 `offline/01-inbox` 로 가져옵니다. |
| `meeting transcribe` | 녹음을 화자별 회의록으로 만듭니다. 전사와 화자분리를 함께 합니다. |
| `meeting meeting_md` | 전사 JSON을 화자별 마크다운으로 바꿉니다. |
| `meeting selftest` | 스크립트를 고친 뒤 회귀 점검을 돌립니다. |

아래 설명에 나오는 `bin/xxx` 는 모두 `meeting xxx` 로 바꿔 쓸 수 있습니다. 반대로 `bin/setup`, `bin/transcribe`, `bin/import-iphone`, `bin/prefetch`, `bin/meeting_md.py`, `bin/selftest` 처럼 폴더 안에서 직접 실행해도 똑같이 동작합니다.

---

## 실시간 자막

회의 중에 상대방 말을 한국어 자막으로 보는 기능입니다. 기록이 아니라 **이해를 돕는 용도**이고, 회의록은 아래 두 경로가 따로 맡습니다.

| 상황 | 명령 | 하는 일 |
| --- | --- | --- |
| 외국 파트너와 온라인 회의 | `meeting live` | 시스템 오디오를 잡아 영어 전사 + 한국어 번역 |
| 외국인과 대면, 영어 | `meeting live --mic` | 마이크를 잡아 영어 전사 + 한국어 번역 |
| 한국어 회의 | `meeting live --ko` | 마이크를 잡아 한국어 전사만 (번역 없음) |

### 회의 중 조작

| 키 | 동작 |
| --- | --- |
| 스페이스 | 멈춤 / 다시 시작 |
| `q` | 끝내기 |

멈춘 동안 들어온 말은 버립니다. 쌓아 두면 다시 시작할 때 한꺼번에 쏟아져 오히려 방해가 됩니다.

끝내면 자막이 `online/02-notes/` 에 날짜별 마크다운으로 남습니다. 남기지 않으려면 `--no-save` 를 붙입니다.

### 소리는 알아서 잡습니다

`meeting live` 는 시작할 때 시스템 출력을 **회의 출력 (스피커 + BlackHole)** 로 바꾸고, 끝나면 쓰던 출력으로 되돌립니다. 손대고 싶지 않으면 `--keep-audio` 를 붙입니다.

장치를 만들고 상태를 확인하는 명령은 이렇습니다. 설치는 위 [설치 5단계](#5-실시간-자막을-쓴다면)에서 마칩니다.

```bash
meeting setup-audio           장치 만들기
meeting setup-audio --status  지금 출력이 무엇인지
meeting setup-audio --speaker 내장 스피커로 되돌리기
```

### 번역을 무엇으로 할지

```bash
meeting live --backend claude-cli      API 키 없이 Claude (구독 사용)
meeting live --context "릴스 마케팅 회의"
```

| 백엔드 | 지연 | 키 | 비용 |
| --- | --- | --- | --- |
| `ollama` (기본) | 1초 안쪽 | 불필요 | 없음 |
| `claude-cli` | 5초 남짓 | 불필요 | 구독 한도 |
| `claude` | 중간 | API 키 필요 | 토큰 과금 |

`--context` 로 회의 주제나 자주 나오는 용어를 알려 주면 번역이 눈에 띄게 정확해집니다.

### 알아 둘 점

- 전사는 실시간의 15배 속도로 돌아 여유가 큽니다. 그래서 정확도가 높은 `medium.en` 을 기본으로 씁니다.
- 실시간 전사는 사후 처리보다 정확도가 떨어집니다. **실시간 자막을 회의록으로 삼지 마세요.**
- 말하는 동안 원문 한 줄이 제자리에서 길어지고, 말이 멈추면 그 아래에 번역이 붙습니다.

---

## online — 온라인 회의

Anarlog가 내 마이크와 시스템 오디오를 동시에 잡아서 전사와 요약까지 처리합니다. 따로 돌릴 스크립트는 없고, 결과물만 `online/02-notes/`에 모아 둡니다.

### 권한

설치는 위 [설치 6단계](#6-온라인-회의-회의록을-만든다면)에서 마칩니다. 첫 실행 때 두 가지를 물어보며, 둘 다 허용해야 합니다.

- **마이크**: 내 목소리를 담는 데 필요합니다.
- **화면 기록**: 상대방 목소리, 즉 시스템 오디오를 잡는 데 필요합니다. 화면을 촬영하는 것이 아니라 macOS가 시스템 오디오 캡처를 이 권한으로 묶어 두었기 때문입니다.

### 설정

- 전사 모델은 로컬 모델 중 **Whisper Large Turbo**를 내려받습니다.
- 언어는 **한국어로 고정**합니다. 자동 감지로 두면 한국어와 영어가 섞인 회의에서 중간에 언어를 잘못 판단하는 일이 생깁니다.
- 요약 LLM은 BYOK 방식이라 키만 넣으면 됩니다. Claude API 키를 붙이는 편이 품질 대비 가장 편하고, 완전히 로컬로 돌리려면 Ollama에 qwen 계열 모델을 올리면 됩니다.

### 회의 중에 할 일

Granola 계열이라 회의 중에 적은 메모를 뼈대로 삼아 요약을 만듭니다. 아무것도 적지 않으면 평범한 전사 요약에 그치니, 키워드 수준이라도 던져 두면 결과가 훨씬 좋아집니다.

### 회의가 끝나면

Anarlog에서 노트를 마크다운으로 내보내 `online/02-notes/`에 `2026-09-20-weekly.md`처럼 날짜를 앞에 붙인 형식으로 저장합니다. 원본이나 전사 파일도 남기고 싶으면 `online/01-inbox/`에 넣습니다.

---

## offline — 현장 회의

### 1. 녹음

아이폰 음성 메모를 권합니다. 테이블 한가운데 놓기 좋은데, 노트북은 보통 내 앞에 치우쳐 있어서 반대편 발화자가 멀어집니다.

맥 내장 마이크로 녹음할 때는 **마이크 모드**를 반드시 확인합니다. 제어센터에서 **음성 격리(Voice Isolation)**가 켜져 있으면 내 목소리만 남기고 다른 참석자 목소리를 소음으로 깎아냅니다. **표준**이나 **광대역(Wide Spectrum)**으로 바꿔 두어야 합니다. 이 항목은 앱이 마이크를 사용하는 중에만 제어센터에 나타납니다.

내장 마이크로 감당되는 조건과 버거운 조건은 이렇게 갈립니다.

| 쓸 만한 조건 | 힘든 조건 |
| --- | --- |
| 2~4명, 작은 회의실이나 카페 테이블 | 6명 이상, 넓은 회의실, 긴 테이블 끝자리 |
| 노트북을 테이블 중앙에, 화면을 열어 둔 상태 | 에어컨이나 프로젝터 팬 소음이 있는 방 |
| 발화자까지 1m 내외 | 여러 명이 동시에 말하는 브레인스토밍 |

### 2. 파일 가져오기

아이폰 음성 메모 앱에서 해당 녹음을 열고 **[공유] > [파일에 저장] > iCloud Drive/meeting-notes**를 고릅니다. 그다음 맥에서 실행합니다.

```bash
bin/import-iphone
```

최근 2일 내 파일을 찾아 `offline/01-inbox/`로 복사합니다. 기간을 늘리려면 `bin/import-iphone 7`처럼 일수를 붙입니다. 맥으로 직접 녹음했다면 파일을 `offline/01-inbox/`에 넣기만 하면 됩니다.

### 3. 전사와 화자분리

```bash
bin/transcribe
```

`offline/01-inbox`에 있는 파일을 전부 처리해서 `offline/02-transcripts/`에 JSON을, `offline/03-notes/`에 화자별 마크다운을 남깁니다. 특정 파일만 돌리려면 `bin/transcribe 주간회의.m4a`처럼 이름을 붙입니다.

속도에 대해서는 미리 알아 두는 편이 좋습니다. WhisperX는 내부적으로 CTranslate2를 쓰는데 Apple Silicon GPU를 타지 않아서 M4 Pro에서도 CPU로 돌아갑니다. 1시간짜리 회의에 대략 10~20분이 걸리니, 회의가 끝나고 걸어 두는 방식으로 쓰면 실용적입니다.

### 4. 화자 이름 붙이기

처음 돌리면 화자가 `SPEAKER_00` 같은 라벨로 나옵니다. 콘솔에 등장한 라벨이 함께 출력되니, `offline/03-notes/`의 마크다운을 열어 누가 누구인지 확인한 다음 이름을 넣어 다시 돌립니다.

```bash
bin/transcribe 주간회의.m4a --names SPEAKER_00=이우성 SPEAKER_01=김팀장
```

전사 결과 JSON은 이미 만들어져 있으므로 재사용하며, 변환만 다시 수행하기 때문에 몇 초면 끝납니다. 변환기를 직접 부를 수도 있는데, 이때는 `bin/meeting_md.py`에 JSON 경로와 출력 위치를 넘깁니다.

```bash
bin/meeting_md.py offline/02-transcripts/주간회의.json -o offline/03-notes/주간회의.md --names SPEAKER_00=이우성
```

결과는 이런 모양입니다.

```markdown
### 이우성  `00:00`

자, 그럼 릴스 포맷 건부터 볼까요. 지난주에 올린 두 개가 조회수 차이가 꽤 났어요.

### 김팀장  `00:09`

맞아요, 후킹 문구를 3초 안에 넣은 쪽이 확실히 좋았습니다.
```

실제 출력 예시는 [examples/sample-note.md](examples/sample-note.md) 에 있습니다.

### 5. 요약

`offline/03-notes/`의 마크다운을 그대로 Claude에게 넘기면 됩니다. 화자가 붙어 있어서 누가 무엇을 하기로 했는지, 액션 아이템 정리가 훨씬 정확하게 나옵니다.

---

## 자주 겪는 문제

| 증상 | 원인과 해결 |
| --- | --- |
| 화자분리에서 401 오류 | pyannote 두 모델의 약관 동의를 빠뜨렸습니다. 위 HuggingFace 항목을 확인합니다. |
| `bin/import-iphone`이 "권한 없어 건너뜀"을 출력 | 음성 메모 저장소가 보호 영역이라 그렇습니다. iCloud Drive/meeting-notes 경로로 보내는 방식을 쓰거나, 시스템 설정 > 개인정보 보호 및 보안 > 전체 디스크 접근 권한에 터미널을 추가합니다. |
| 다른 참석자 목소리가 뭉개짐 | 마이크 모드가 음성 격리로 켜져 있었을 가능성이 큽니다. 표준이나 광대역으로 바꿉니다. |
| 화자분리가 사람 수를 틀리게 잡음 | `whisperx`에 `--min_speakers`와 `--max_speakers`를 넘길 수 있습니다. `bin/transcribe`를 수정하거나 직접 실행합니다. |
| 전사가 너무 느림 | `.env`의 `WHISPER_MODEL`을 `medium`으로 낮춥니다. 정확도를 유지하면서 더 빠르게 하려면 전사만 `mlx-whisper`로 빼고 화자분리를 따로 돌려서 합치는 구조가 필요한데, 손이 꽤 갑니다. |

---

## 스크립트를 고쳤다면

```bash
bin/selftest
```

프로젝트를 임시 폴더로 복사한 다음, 모델을 내려받지 않는 가짜 `whisperx`와 격리된 `HOME`으로 전 과정을 돌려 봅니다. 실제 녹음과 회의록에는 손대지 않으며, 모든 항목이 통과하면 종료 코드 0으로 끝납니다.

검사하는 범위는 이렇습니다.

- 네 스크립트의 문법, 실행 권한, 디렉터리 구조
- 화자별 마크다운 변환 규칙: 연속 발화 병합, 빈 세그먼트 제외, 이름 치환, 타임스탬프 표기
- 예외 처리: 없는 파일, 빈 전사 결과, `speaker` 키가 없는 JSON, 최상위가 리스트인 JSON
- `bin/transcribe`의 분기: 토큰 누락, `whisperx` 미설치, 빈 inbox, 공백이 든 파일명, 전사 결과 재사용, 환경변수로 모델과 언어 바꾸기
- `bin/import-iphone`의 분기: 가져올 파일 없음, 신규 복사, 중복 건너뛰기, 기간 인자
- iCloud 전달 폴더 이름이 두 스크립트와 README에서 일치하는지
- `.gitignore`가 녹음 원본과 전사 JSON, `.env`는 제외하면서 회의록은 추적하는지
