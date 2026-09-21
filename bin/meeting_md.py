#!/usr/bin/env python3
"""
whisperx --diarize 결과(JSON)를 화자별 마크다운 회의록으로 변환

사용법:
    meeting_md.py 회의녹음.json
    meeting_md.py 회의녹음.json --names SPEAKER_00=이우성 SPEAKER_01=김팀장
    meeting_md.py 회의녹음.json -o ../03-notes/주간회의.md --title "주간 회의"
"""

import argparse
import json
import sys
from pathlib import Path


def mmss(sec):
    # 초 단위 값 -> 00:00 표기
    sec = int(sec or 0)
    return f"{sec // 60:02d}:{sec % 60:02d}"


def load_segments(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)

    # whisperx 출력 형태 대응 (버전별로 최상위 키가 다름)
    if isinstance(data, dict):
        return data.get("segments") or data.get("transcription") or []
    if isinstance(data, list):
        return data
    return []


def group_by_speaker(segments):
    # 같은 화자가 이어서 말한 구간은 한 덩어리로 합침
    blocks = []
    for seg in segments:
        text = (seg.get("text") or "").strip()
        if not text:
            continue

        speaker = seg.get("speaker") or "UNKNOWN"
        start = seg.get("start")
        end = seg.get("end")

        if blocks and blocks[-1]["speaker"] == speaker:
            blocks[-1]["text"] += " " + text
            blocks[-1]["end"] = end
        else:
            blocks.append(
                {"speaker": speaker, "start": start, "end": end, "text": text}
            )
    return blocks


def to_markdown(blocks, names, title):
    lines = [f"# {title}", ""]

    # 등장 화자 목록 (이름 매핑 전 원본 라벨 확인용)
    speakers = []
    for b in blocks:
        if b["speaker"] not in speakers:
            speakers.append(b["speaker"])
    lines.append("참석자: " + ", ".join(names.get(s, s) for s in speakers))

    total = max((b["end"] or 0) for b in blocks) if blocks else 0
    lines.append(f"길이: {mmss(total)} / 발화 블록 {len(blocks)}개")
    lines.append("")
    lines.append("---")
    lines.append("")

    for b in blocks:
        who = names.get(b["speaker"], b["speaker"])
        lines.append(f"### {who}  `{mmss(b['start'])}`")
        lines.append("")
        lines.append(b["text"])
        lines.append("")

    return "\n".join(lines)


def main():
    p = argparse.ArgumentParser(
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description="whisperx 가 만든 전사 JSON 을 화자별 마크다운 회의록으로 바꿉니다.",
        epilog="""쓰는 법
  meeting meeting_md offline/02-transcripts/주간회의.json
  meeting meeting_md offline/02-transcripts/주간회의.json \\
      -o offline/03-notes/주간회의.md --names SPEAKER_00=이우성 SPEAKER_01=김팀장

  meeting transcribe 가 전사를 마친 뒤 이 변환을 자동으로 수행합니다.
  화자 이름만 다시 붙일 때는 전사를 되풀이하지 않고 이 명령만 쓰면 몇 초로 끝납니다.""",
    )
    p.add_argument("json_path", help="whisperx가 만든 JSON 파일")
    p.add_argument(
        "--names",
        nargs="*",
        default=[],
        help="화자 라벨을 실명으로 치환 (예: SPEAKER_00=이우성)",
    )
    p.add_argument("--title", default=None, help="회의록 제목")
    p.add_argument("-o", "--output", default=None, help="출력할 마크다운 경로")
    args = p.parse_args()

    src = Path(args.json_path)
    if not src.exists():
        sys.exit(f"파일 없음: {src}")

    # SPEAKER_00=이름 형태를 딕셔너리로
    names = {}
    for pair in args.names:
        if "=" in pair:
            k, v = pair.split("=", 1)
            names[k.strip()] = v.strip()

    segments = load_segments(src)
    if not segments:
        sys.exit("세그먼트가 비어 있음 (JSON 구조 확인 필요)")

    blocks = group_by_speaker(segments)
    title = args.title or src.stem
    out = Path(args.output) if args.output else src.with_suffix(".md")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(to_markdown(blocks, names, title), encoding="utf-8")

    # 긴 절대 경로는 읽기 어려워서 현재 위치 기준으로 줄여서 보여 줌
    try:
        disp = out.resolve().relative_to(Path.cwd())
    except ValueError:
        disp = out

    # 화자 라벨을 몰라서 --names를 못 넣는 경우가 많아 콘솔에 같이 출력
    labels = sorted({b["speaker"] for b in blocks})
    print(f"완료: {disp}")
    print(f"발화 블록 {len(blocks)}개 / 화자 라벨: {', '.join(labels)}")


if __name__ == "__main__":
    main()
