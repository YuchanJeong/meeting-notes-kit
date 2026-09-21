#!/usr/bin/env python3
"""
whisperx를 부르되, pyannote 체크포인트를 읽을 수 있게 만들어 준다.

PyTorch 2.6부터 `torch.load`의 `weights_only` 기본값이 True로 바뀌었다.
그런데 pyannote의 VAD·화자분리 체크포인트에는 omegaconf 설정 객체가 들어 있어
기본 허용 목록에 걸리고, whisperx가 모델을 얹는 단계에서 죽는다.

  _pickle.UnpicklingError: Weights only load failed.
  Unsupported global: GLOBAL omegaconf.listconfig.ListConfig

받는 모델이 HuggingFace의 pyannote 공식 저장소에서 온 것이므로,
그 파일들에 한해 예전 방식으로 읽도록 되돌린다. 임의의 출처에서 받은
체크포인트를 읽는 용도가 아니다.

이 파일은 whisperx가 설치된 파이썬으로 실행해야 한다. bin/transcribe 가 알아서 한다.
"""

import sys

import torch

_original_load = torch.load


def _load_trusting_pyannote(*args, **kwargs):
    # 덮어쓴다. setdefault 로는 듣지 않는다 - lightning 이 weights_only=True 를
    # 명시적으로 넘기기 때문에, 기본값만 바꿔서는 그 인자가 그대로 살아남는다.
    kwargs["weights_only"] = False
    return _original_load(*args, **kwargs)


torch.load = _load_trusting_pyannote

from whisperx.__main__ import cli  # noqa: E402  (패치 뒤에 불러와야 한다)

if __name__ == "__main__":
    sys.exit(cli())
