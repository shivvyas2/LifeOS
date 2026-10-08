import Foundation
import Soundscape

/// Writes a soundscape to a WAV for listening while tuning.
var options: [String: String] = [:]
var args = CommandLine.arguments.dropFirst().makeIterator()
while let key = args.next() {
    guard key.hasPrefix("--"), let value = args.next() else {
        FileHandle.standardError.write(Data("usage: soundscape-render --mood focus --minutes 3 --hour 9 [--hr 95] [--weather rain] [--seed 7] [--out file.wav]\n".utf8))
        exit(2)
    }
    options[String(key.dropFirst(2))] = value
}

guard let mood = Mood(rawValue: options["mood"] ?? "focus") else {
    FileHandle.standardError.write(Data("unknown mood; use focus, brainstorm, relax or sleep\n".utf8)); exit(2)
}
let minutes = Double(options["minutes"] ?? "3") ?? 3
let hour = Int(options["hour"] ?? "14") ?? 14
let seed = UInt64(options["seed"] ?? "7") ?? 7
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .current
let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
let weather: WeatherInput? = switch options["weather"] {
case "rain": WeatherInput(kind: .rain, windKph: 5)
case "snow": WeatherInput(kind: .snow, windKph: 5)
case "wind": WeatherInput(kind: .clear, windKph: 45)
case "clear": WeatherInput(kind: .clear, windKph: 5)
default: nil
}
let conditions = Conditions(date: date, heartRate: options["hr"].flatMap(Double.init), restingHeartRate: 60,
                            phase: mood == .sleep ? .fading(0.2) : .work, weather: weather)
let parameters = SoundParameters.make(.for(mood), conditions)
let renderer = SoundscapeRenderer(mood: mood, sampleRate: 48_000, seed: seed, parameters: parameters)
let (left, right) = renderer.render(seconds: minutes * 60)
let out = options["out"] ?? "\(mood.rawValue)-\(hour)h\(options["hr"].map { "-hr\($0)" } ?? "")\(options["weather"].map { "-\($0)" } ?? "").wav"
try WAVWriter.data(left: left, right: right, sampleRate: 48_000).write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
