import Foundation

// Обычный запуск открывает окно; `--selftest` прогоняет движки без интерфейса.
// Проверка идёт на главном потоке — импорт документов в AppKit другого не допускает,
// поэтому здесь крутится обычный RunLoop, а не блокирующий семафор.
if let index = CommandLine.arguments.firstIndex(of: "--make-icon") {
    let output = CommandLine.arguments.count > index + 1
        ? URL(fileURLWithPath: CommandLine.arguments[index + 1])
        : URL(fileURLWithPath: "AppIcon.icns")
    do {
        try IconFactory.writeICNS(to: output)
        // Заодно кладём крупный PNG рядом — на него удобно смотреть.
        IconFactory.writePNG(size: 512, to: output.deletingPathExtension()
            .appendingPathExtension("png"))
        print("Иконка собрана: \(output.path)")
        exit(0)
    } catch {
        print("Ошибка: \(error.localizedDescription)")
        exit(1)
    }
}

// Терминальный режим: тот же бинарник, вызванный как `shark` либо с командой.
if SharkCLI.shouldRun(CommandLine.arguments) {
    setvbuf(stdout, nil, _IOLBF, 0)
    Task { @MainActor in
        exit(await SharkCLI.run(CommandLine.arguments))
    }
    RunLoop.main.run()
}

if CommandLine.arguments.contains("--selftest") {
    setvbuf(stdout, nil, _IOLBF, 0)
    Task { @MainActor in
        exit(await SelfTest.run())
    }
    RunLoop.main.run()
} else {
    SharkApp.main()
}
