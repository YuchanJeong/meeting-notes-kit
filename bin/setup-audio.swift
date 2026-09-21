// 스피커와 BlackHole로 소리를 동시에 보내는 다중 출력 장치를 만든다.
//
// Audio MIDI 설정 앱에서 손으로 하던 일을 Core Audio로 직접 한다.
// 이 장치를 시스템 출력으로 고르면, 상대방 목소리를 들으면서 동시에
// BlackHole 입력으로 전사기에 넘길 수 있다.
//
//   swift bin/setup-audio.swift            만들거나 이미 있으면 그대로 둔다
//   swift bin/setup-audio.swift --list     오디오 장치만 훑어본다
//   swift bin/setup-audio.swift --use      시스템 출력을 이 장치로 바꾼다
//   swift bin/setup-audio.swift --speaker  시스템 출력을 내장 스피커로 되돌린다
//   swift bin/setup-audio.swift --remove   만들어 둔 장치를 지운다

import CoreAudio
import Foundation

let DEVICE_NAME = "회의 출력 (스피커 + BlackHole)"
let DEVICE_UID = "com.meeting-notes.multi-output"

// MARK: - Core Audio 조회 도우미

func systemDeviceIDs() -> [AudioDeviceID] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }

    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
    var addr = AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString? = nil
    let status = withUnsafeMutablePointer(to: &value) {
        AudioObjectGetPropertyData(id, &addr, 0, nil, &size, $0)
    }
    guard status == noErr, let v = value else { return nil }
    return v as String
}

func outputChannelCount(_ id: AudioDeviceID) -> Int {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioObjectPropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }

    let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
    defer { raw.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }

    let lists = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
    return lists.reduce(0) { $0 + Int($1.mNumberChannels) }
}

struct Device {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let outputs: Int
}

func allDevices() -> [Device] {
    systemDeviceIDs().compactMap { id in
        guard let name = stringProperty(id, kAudioObjectPropertyName),
              let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return Device(id: id, name: name, uid: uid, outputs: outputChannelCount(id))
    }
}

func currentOutputDevice() -> Device? {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
    return allDevices().first { $0.id == id }
}

func setOutputDevice(_ device: Device) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var id = device.id
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    return AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &id) == noErr
}

// MARK: - 동작

func listDevices() {
    print("오디오 장치")
    for d in allDevices() {
        let mark = d.outputs > 0 ? "출력 \(d.outputs)채널" : "입력 전용"
        print("  \(d.name)  [\(mark)]")
        print("    uid: \(d.uid)")
    }
}

func removeDevice() {
    guard let existing = allDevices().first(where: { $0.uid == DEVICE_UID }) else {
        print("만들어 둔 장치가 없습니다.")
        return
    }
    let status = AudioHardwareDestroyAggregateDevice(existing.id)
    if status == noErr {
        print("지웠습니다: \(existing.name)")
    } else {
        print("지우지 못했습니다 (OSStatus \(status))")
        exit(1)
    }
}

func createDevice() {
    let devices = allDevices()

    if let existing = devices.first(where: { $0.uid == DEVICE_UID }) {
        print("이미 있습니다: \(existing.name)")
        print("시스템 설정 > 사운드 > 출력 에서 이 장치를 고르면 됩니다.")
        return
    }

    // BlackHole은 이름으로 찾는다. 설치되지 않았으면 만들 수 없다.
    guard let blackhole = devices.first(where: { $0.name.localizedCaseInsensitiveContains("blackhole") }) else {
        print("BlackHole을 찾지 못했습니다.")
        print("  brew install blackhole-2ch 로 먼저 설치해 주세요.")
        exit(1)
    }

    // 내장 스피커를 고른다. 없으면 BlackHole이 아닌 출력 장치 중 첫 번째.
    let speaker = devices.first(where: {
        $0.outputs > 0 && $0.uid.contains("BuiltInSpeakerDevice")
    }) ?? devices.first(where: {
        $0.outputs > 0 && !$0.name.localizedCaseInsensitiveContains("blackhole")
    })

    guard let speaker else {
        print("내보낼 스피커를 찾지 못했습니다.")
        exit(1)
    }

    // 스피커를 기준 장치로 둔다. 소리의 타이밍을 이쪽에 맞춘다.
    let description: [String: Any] = [
        kAudioAggregateDeviceNameKey: DEVICE_NAME,
        kAudioAggregateDeviceUIDKey: DEVICE_UID,
        kAudioAggregateDeviceSubDeviceListKey: [
            [kAudioSubDeviceUIDKey: speaker.uid],
            [kAudioSubDeviceUIDKey: blackhole.uid],
        ],
        kAudioAggregateDeviceMasterSubDeviceKey: speaker.uid,
        kAudioAggregateDeviceIsStackedKey: 1,   // 1이면 다중 출력, 0이면 집합 장치
        kAudioAggregateDeviceIsPrivateKey: 0,   // 0이어야 다른 앱에도 보이고 유지된다
    ]

    var newID: AudioDeviceID = 0
    let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &newID)
    guard status == noErr else {
        print("만들지 못했습니다 (OSStatus \(status))")
        exit(1)
    }

    print("만들었습니다: \(DEVICE_NAME)")
    print("  스피커:    \(speaker.name)")
    print("  전사 경로: \(blackhole.name)")
    print("")
    print("시스템 설정 > 사운드 > 출력 에서 이 장치를 고르면,")
    print("소리를 들으면서 동시에 BlackHole로 전사할 수 있습니다.")
}

func switchTo(_ predicate: (Device) -> Bool, label: String) {
    guard let target = allDevices().first(where: predicate) else {
        print("\(label)을 찾지 못했습니다.")
        exit(1)
    }
    let before = currentOutputDevice()?.name ?? "알 수 없음"
    guard setOutputDevice(target) else {
        print("출력을 바꾸지 못했습니다.")
        exit(1)
    }
    print("시스템 출력을 바꿨습니다.")
    print("  이전: \(before)")
    print("  현재: \(target.name)")
}

// MARK: - 진입점

let args = CommandLine.arguments
if args.contains("--list") {
    listDevices()
} else if args.contains("--remove") {
    removeDevice()
} else if args.contains("--use") {
    switchTo({ $0.uid == DEVICE_UID }, label: "회의 출력 장치")
    print("")
    print("주의: 다중 출력 장치에서는 키보드 음량 키가 듣지 않습니다.")
    print("  소리 크기는 시스템 설정 > 사운드 에서 조절하거나,")
    print("  --speaker 로 내장 스피커에 되돌린 뒤 조절하세요.")
} else if args.contains("--blackhole") {
    // 소리를 스피커로 내보내지 않고 BlackHole로만 보낸다. 조용히 시험할 때 쓴다.
    switchTo({ $0.name.localizedCaseInsensitiveContains("blackhole") }, label: "BlackHole")
} else if args.contains("--speaker") {
    switchTo({ $0.uid == "BuiltInSpeakerDevice" }, label: "내장 스피커")
} else if args.contains("--status") {
    print("현재 시스템 출력: \(currentOutputDevice()?.name ?? "알 수 없음")")
} else if args.contains("--status-uid") {
    // 스크립트가 원래 출력을 기억했다가 되돌릴 때 쓴다
    print(currentOutputDevice()?.uid ?? "")
} else if let i = args.firstIndex(of: "--use-uid"), i + 1 < args.count {
    let uid = args[i + 1]
    switchTo({ $0.uid == uid }, label: "장치(\(uid))")
} else {
    createDevice()
}
