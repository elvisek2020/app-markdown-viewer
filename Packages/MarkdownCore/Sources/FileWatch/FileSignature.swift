import Darwin

/// Otisk souboru ze `stat()` – změna kterékoli složky znamená, že je potřeba soubor znovu přečíst.
public struct FileSignature: Sendable, Equatable {
    public let device: Int32
    public let inode: UInt64
    public let size: Int64
    public let modifiedNanoseconds: Int64
    public let changedNanoseconds: Int64

    /// `nil`, pokud soubor neexistuje nebo nejde o běžný soubor.
    public static func read(path: String) -> FileSignature? {
        var info = stat()
        guard stat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { return nil }
        return FileSignature(
            device: info.st_dev,
            inode: info.st_ino,
            size: info.st_size,
            modifiedNanoseconds: Int64(info.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(info.st_mtimespec.tv_nsec),
            changedNanoseconds: Int64(info.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(info.st_ctimespec.tv_nsec)
        )
    }
}
