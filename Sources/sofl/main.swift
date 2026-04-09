import ArgumentParser

// Use ParsableCommand (not Async) so `service start` executes on main thread
struct Sofl: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sofl",
        abstract: "Local speech-to-text daemon powered by parakeet CoreML",
        version: "1.3.0",
        subcommands: [Service.self, Test.self, Devices.self, ShowConfig.self],
        defaultSubcommand: Service.self
    )
}

Sofl.main()
