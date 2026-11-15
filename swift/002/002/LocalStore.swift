//
//  LocalStore.swift
//  神算子
//
//  本地 JSON 持久化：笔记、账目等用户数据
//  文件放在 Application Support，系统不会像 Caches 那样清理
//

import Foundation

enum LocalStore {

    static func url(_ name: String) -> URL {
        let fm = FileManager.default
        let dir = (try? fm.url(for: .applicationSupportDirectory,
                               in: .userDomainMask,
                               appropriateFor: nil,
                               create: true))
            ?? fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(name)
    }

    static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let data = try? Data(contentsOf: url(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, _ name: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: .atomic)
    }
}
