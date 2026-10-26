import Foundation
import Darwin

@main enum NetworkDeletionChecks {
  static func main() throws {
    let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent("network-delete-check-" + UUID().uuidString).resolvingSymlinksInPath()
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.appendingPathComponent("denied").path); try? fm.removeItem(at: root) }
    var count = 0
    func check(_ ok: @autoclosure () throws -> Bool, _ title: String) throws { guard try ok() else { fatalError(title) }; count += 1 }
    func rejects(_ title: String, _ body: () throws -> Void) throws { do { try body() } catch { count += 1; return }; fatalError(title) }
    func file(_ path: String) throws -> URL { let url = root.appendingPathComponent(path); try Data("keep".utf8).write(to: url); return url }
    func plan(_ url: URL, classifier: @escaping @Sendable (URL) -> DeletionVolume? = { _ in .network }) throws -> NetworkDeletion {
      try PreparedDeletion.fixtures([url], root: root, classification: classifier)[0].network!
    }
    let one = try file("one.txt")
    try rejects("production classifier rejects local permanent deletion") { _ = try NetworkDeletion(one) }
    try check(fm.fileExists(atPath: one.path), "rejected local item survives")
    let firstPlan = try plan(one)
    try check(try Data(contentsOf: one) == Data("keep".utf8), "preparation reads metadata only")
    try firstPlan.remove(); try check(!fm.fileExists(atPath: one.path), "confirmed regular fixture removed")
    try rejects("snapshot cannot be reused") { try firstPlan.remove() }
    try rejects("root protected") { _ = try plan(URL(fileURLWithPath: "/")) }
    try rejects("home protected") { _ = try plan(fm.homeDirectoryForCurrentUser) }
    try rejects("non-file URL rejected") { _ = try plan(URL(string: "smb://fixture/share")!) }
    let replaced = try file("replaced"), old = root.appendingPathComponent("old")
    let stale = try plan(replaced)
    try fm.moveItem(at: replaced, to: old); try Data("new".utf8).write(to: replaced)
    try rejects("replacement root rejected") { try stale.remove() }
    try check(try String(contentsOf: replaced) == "new", "replacement preserved")
    let tree = root.appendingPathComponent("tree/子目录"), outside = try file("outside.txt")
    try fm.createDirectory(at: tree, withIntermediateDirectories: true)
    _ = try file("tree/子目录/中文 空格.txt"); _ = try file("tree/子目录/._metadata")
    try fm.createSymbolicLink(at: tree.appendingPathComponent("escape"), withDestinationURL: root)
    try fm.createSymbolicLink(atPath: tree.appendingPathComponent("dangling").path, withDestinationPath: "/not-existing-delete-fixture")
    try plan(tree.deletingLastPathComponent()).remove()
    try check(!fm.fileExists(atPath: tree.deletingLastPathComponent().path), "nested tree and AppleDouble fixtures removed")
    try check(fm.fileExists(atPath: outside.path), "directory symlink not traversed")
    let link = root.appendingPathComponent("link"); try fm.createSymbolicLink(at: link, withDestinationURL: outside)
    try plan(link).remove()
    try check(fm.fileExists(atPath: outside.path), "top-level symlink deletes only link")
    let parent = root.appendingPathComponent("parent"); try fm.createDirectory(at: parent, withIntermediateDirectories: true)
    let child = try file("parent/child"), anchored = try plan(child)
    try fm.moveItem(at: parent, to: root.appendingPathComponent("parent-old")); try fm.createDirectory(at: parent, withIntermediateDirectories: true); _ = try file("parent/child")
    try rejects("parent replacement rejected") { try anchored.remove() }
    try check(fm.fileExists(atPath: child.path) && fm.fileExists(atPath: root.appendingPathComponent("parent-old/child").path), "both parent occupants preserved")
    let denied = root.appendingPathComponent("denied"); try fm.createDirectory(at: denied, withIntermediateDirectories: true); _ = try file("denied/keep")
    let blocked = try plan(denied); try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
    if getuid() != 0 {
      do { try blocked.remove(); fatalError("denied directory removed") }
      catch { let e = error as NSError; try check((e.userInfo[NSUnderlyingErrorKey] as? NSError)?.domain == NSPOSIXErrorDomain && e.code == Int(EACCES) && (e.userInfo[NSFilePathErrorKey] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == denied.resolvingSymlinksInPath().path, "denied path and code preserved without chmod; domain=\(e.domain), code=\(e.code), path=\(e.userInfo[NSFilePathErrorKey] ?? "none"), expected=\(denied.path), underlying=\(e.userInfo[NSUnderlyingErrorKey] ?? "none")") }
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
      try check(fm.fileExists(atPath: denied.appendingPathComponent("keep").path), "failed deletion retains inaccessible contents")
    }
    let aliasTarget = root.appendingPathComponent("alias-target"), aliasOther = root.appendingPathComponent("alias-other"), alias = root.appendingPathComponent("alias")
    try fm.createDirectory(at: aliasTarget, withIntermediateDirectories: true); try fm.createDirectory(at: aliasOther, withIntermediateDirectories: true)
    _ = try file("alias-target/keep"); _ = try file("alias-other/keep")
    try fm.createSymbolicLink(at: alias, withDestinationURL: aliasTarget)
    let aliased = try plan(alias.appendingPathComponent("keep"))
    try fm.removeItem(at: alias); try fm.createSymbolicLink(at: alias, withDestinationURL: aliasOther)
    try rejects("parent symlink retargeted after confirmation") { try aliased.remove() }
    try check(fm.fileExists(atPath: aliasTarget.appendingPathComponent("keep").path) && fm.fileExists(atPath: aliasOther.appendingPathComponent("keep").path), "both alias locations preserved")
    let hard = try file("hard"), secondLink = root.appendingPathComponent("hard-other")
    try fm.linkItem(at: hard, to: secondLink); try plan(hard).remove()
    try check(try String(contentsOf: secondLink) == "keep", "deletion unlinks only the selected hard link")
    let marker = try file("network-classifier-marker"), changed = try file("changed-mount")
    let remounted = try plan(changed, classifier: { _ in FileManager.default.fileExists(atPath: marker.path) ? .network : .local })
    try fm.removeItem(at: marker)
    try rejects("changed mount classification rejected") { try remounted.remove() }
    try check(fm.fileExists(atPath: changed.path), "item survives a simulated change to local classification")
    func failure(_ action: () throws -> NetworkDeletionOutcome) throws -> NetworkDeletionFailure {
      do { _ = try action() } catch let error as NetworkDeletionFailure { return error }
      fatalError("Expected structured deletion failure")
    }
    let local = try file("local-source")
    let actualLocal = try PreparedDeletion.prepare([local])[0]
    try check(actualLocal.volume == .local && actualLocal.network == nil, "production preparation classifies the real local parent FD")
    try check(try actualLocal.validateForRecycle().resolvingSymlinksInPath().path == local.resolvingSymlinksInPath().path, "local Trash plan binds its resolved source")
    try rejects("unknown classification rejects preparation") { _ = try PreparedDeletion.fixtures([local], root: root, classification: { _ in nil }) }
    try check(fm.fileExists(atPath: local.path), "unknown classification has no file side effects")
    let remoteParent = root.appendingPathComponent("remote-parent"), localAlias = root.appendingPathComponent("local-looking-alias")
    try fm.createDirectory(at: remoteParent, withIntermediateDirectories: true)
    _ = try file("remote-parent/item"); try fm.createSymbolicLink(at: localAlias, withDestinationURL: remoteParent)
    let aliasPlan = try PreparedDeletion.fixtures([localAlias.appendingPathComponent("item")], root: root, classification: { actual in actual.lastPathComponent == "remote-parent" ? .network : .local })[0]
    try check(aliasPlan.volume == .network && aliasPlan.network != nil, "classification follows opened parent FD, not lexical alias prefix")
    try rejects("network item cannot use local recycle validation") { _ = try aliasPlan.validateForRecycle() }
    let localSwap = try PreparedDeletion.prepare([local])[0]
    try fm.moveItem(at: local, to: root.appendingPathComponent("kept-local")); _ = try file("local-source")
    try rejects("local recycle rejects replacement identity") { _ = try localSwap.validateForRecycle() }
    let deniedAncestor = root.appendingPathComponent("denied-ancestor"), inner = deniedAncestor.appendingPathComponent("inner")
    try fm.createDirectory(at: inner, withIntermediateDirectories: true); _ = try file("denied-ancestor/inner/item")
    let deniedParent = try plan(inner.appendingPathComponent("item"))
    try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: deniedAncestor.path)
    if getuid() != 0 {
      let result = try failure { try deniedParent.remove() }
      try check((result.underlying as NSError).code == Int(EACCES) && result.outcome.deletedEntries == 0, "parent lstat failure preserves EACCES rather than ESTALE with zero mutations")
    }
    try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedAncestor.path)
    let snapshot = root.appendingPathComponent("snapshot"); try fm.createDirectory(at: snapshot, withIntermediateDirectories: true)
    _ = try file("snapshot/original"); let snapshotPlan = try plan(snapshot); _ = try file("snapshot/added")
    let changedTree = try failure { try snapshotPlan.remove() }
    try check(!changedTree.outcome.mutated && fm.fileExists(atPath: snapshot.appendingPathComponent("added").path) && fm.fileExists(atPath: snapshot.appendingPathComponent("original").path), "new child after confirmation rejects whole manifest before any unlink")
    let changedFile = try file("changed-file"), changedPlan = try plan(changedFile)
    try Data("different content".utf8).write(to: changedFile)
    try check(try failure { try changedPlan.remove() }.outcome.deletedEntries == 0 && fm.fileExists(atPath: changedFile.path), "in-place file change is detected before unlink")
    let partial = root.appendingPathComponent("partial"), deniedChild = partial.appendingPathComponent("z-denied")
    try fm.createDirectory(at: deniedChild, withIntermediateDirectories: true)
    _ = try file("partial/a-first"); _ = try file("partial/z-denied/keep")
    let partialPlan = try plan(partial)
    partialPlan.auditHook = { stage, path in if stage == .afterUnlink && path.lastPathComponent == "a-first" { try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: deniedChild.path) } }
    if getuid() != 0 {
      let failed = try failure { try partialPlan.remove() }
      try check(failed.outcome.deletedEntries == 1 && !failed.outcome.rootRemoved && (failed.underlying as NSError).code == Int(EACCES), "partial directory deletion reports exact completed count and real permission failure")
      try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedChild.path)
      try check(fm.fileExists(atPath: deniedChild.appendingPathComponent("keep").path), "partial failure preserves untouched subtree")
    }
    let during = root.appendingPathComponent("during"); try fm.createDirectory(at: during, withIntermediateDirectories: true)
    _ = try file("during/a"); _ = try file("during/b"); let duringPlan = try plan(during)
    duringPlan.auditHook = { stage, path in if stage == .afterUnlink && path.lastPathComponent == "a" { try Data("preserve new".utf8).write(to: during.appendingPathComponent("new")) } }
    let duringResult = try failure { try duringPlan.remove() }
    try check(duringResult.outcome.deletedEntries == 2 && fm.fileExists(atPath: during.appendingPathComponent("new").path), "new names during execution are never visited and remaining directory is reported partial")
    let limited = root.appendingPathComponent("limited"); try fm.createDirectory(at: limited, withIntermediateDirectories: true)
    for i in 0..<10 { _ = try file("limited/\(i)") }
    try rejects("entry resource limit fails during preparation") { _ = try PreparedDeletion.fixtures([limited], root: root, classification: { _ in .network }, maximumEntries: 5) }
    try check(try fm.contentsOfDirectory(atPath: limited.path).count == 10, "resource failure occurs without deleting any fixture")
    var localBatch: [URL] = []
    for i in 0..<512 { localBatch.append(try file("local-batch-\(i)")) }
    let beforeFD = open("/dev/null", O_RDONLY); guard beforeFD >= 0 else { fatalError("FD fixture") }; close(beforeFD)
    let localPlans = try PreparedDeletion.prepare(localBatch)
    let afterFD = open("/dev/null", O_RDONLY); guard afterFD >= 0 else { fatalError("FD fixture") }; close(afterFD)
    try check(localPlans.count == 512 && beforeFD == afterFD, "large local Trash batches retain no per-item descriptors")
    for prepared in localPlans { _ = try prepared.validateForRecycle() }
    try check(localBatch.allSatisfy { fm.fileExists(atPath: $0.path) }, "all 512 local plans revalidate without file mutations")
    try rejects("network descriptor budget still rejects more than 64 roots") { _ = try PreparedDeletion.fixtures(Array(localBatch.prefix(65)), root: root, classification: { _ in .network }) }
    do { _ = try PreparedDeletion.fixtures([outside], root: root, classification: { _ in .network }, allowNetwork: false); fatalError("disabled network deletion was prepared") }
    catch { try check((error as NSError).code == Int(ENOTSUP) && fm.fileExists(atPath: outside.path), "ordinary preparation policy refuses network deletion before mutation") }
    let linkedFolder = root.appendingPathComponent("linked-folder"); try fm.createDirectory(at: linkedFolder, withIntermediateDirectories: true)
    let linkedA = try file("linked-folder/a"), linkedB = linkedFolder.appendingPathComponent("b")
    try fm.linkItem(at: linkedA, to: linkedB)
    let linkedOutcome = try plan(linkedFolder).remove()
    try check(linkedOutcome.deletedEntries == 3 && linkedOutcome.rootRemoved && !fm.fileExists(atPath: linkedFolder.path), "own unlink ctime changes do not interrupt a hardlinked directory")
    let batchA = try file("batch-link-a"), batchB = root.appendingPathComponent("batch-link-b")
    try fm.linkItem(at: batchA, to: batchB)
    let linkedPlans = try PreparedDeletion.fixtures([batchA, batchB], root: root, classification: { _ in .network })
    for prepared in linkedPlans { try prepared.network!.remove() }
    try check(!fm.fileExists(atPath: batchA.path) && !fm.fileExists(atPath: batchB.path), "hardlink stamp updates span separately prepared roots in the same batch")
    let unreadable = root.appendingPathComponent("unreadable-links"); try fm.createDirectory(at: unreadable, withIntermediateDirectories: true)
    let unreadableA = try file("unreadable-links/a"); try fm.linkItem(at: unreadableA, to: unreadable.appendingPathComponent("b")); try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadableA.path)
    try check(try plan(unreadable).remove().rootRemoved, "unlinking hardlinks does not require file read permission")
    let changedLinks = root.appendingPathComponent("changed-links"); try fm.createDirectory(at: changedLinks, withIntermediateDirectories: true)
    let changedA = try file("changed-links/a"), changedB = changedLinks.appendingPathComponent("b"); try fm.linkItem(at: changedA, to: changedB)
    let externallyChanged = try plan(changedLinks)
    externallyChanged.auditHook = { stage, path in if stage == .afterUnlink && path.lastPathComponent == "a" { try Data("external change".utf8).write(to: changedB, options: []) } }
    let changedOutcome = try failure { try externallyChanged.remove() }
    try check(changedOutcome.outcome.deletedEntries == 1 && fm.fileExists(atPath: changedB.path), "external writes after an own hardlink unlink still stop deletion")

    let localParent = root.appendingPathComponent("local-parent"), localAliasPath = root.appendingPathComponent("local-parent-alias")
    try fm.createDirectory(at: localParent, withIntermediateDirectories: true); _ = try file("local-parent/item")
    try fm.createSymbolicLink(at: localAliasPath, withDestinationURL: localParent)
    let boundLocal = try PreparedDeletion.prepare([localAliasPath.appendingPathComponent("item")])[0]
    try fm.removeItem(at: localAliasPath); try fm.createSymbolicLink(at: localAliasPath, withDestinationURL: aliasOther)
    try rejects("local recycle reopens and rejects a retargeted parent alias") { _ = try boundLocal.validateForRecycle() }
    let stableLocal = try PreparedDeletion.prepare([localParent.appendingPathComponent("item")])[0]
    try fm.moveItem(at: localParent, to: root.appendingPathComponent("local-parent-old")); try fm.createDirectory(at: localParent, withIntermediateDirectories: true); _ = try file("local-parent/item")
    try rejects("local recycle reopens and rejects a replaced parent directory") { _ = try stableLocal.validateForRecycle() }
    try check(fm.fileExists(atPath: localParent.appendingPathComponent("item").path) && fm.fileExists(atPath: root.appendingPathComponent("local-parent-old/item").path), "reopening local descriptors preserves both parent occupants")
    let deep = root.appendingPathComponent("deep"); try fm.createDirectory(at: deep, withIntermediateDirectories: true)
    var deepFD = open(deep.path, O_RDONLY | O_DIRECTORY)
    guard deepFD >= 0 else { fatalError("deep fixture open") }
    var createdLevels = 0
    do {
      defer {
        for _ in 0..<createdLevels { let parentFD = openat(deepFD, "..", O_RDONLY | O_DIRECTORY); precondition(parentFD >= 0); close(deepFD); precondition(unlinkat(parentFD, "d", AT_REMOVEDIR) == 0); deepFD = parentFD }
        close(deepFD)
      }
      for _ in 0..<512 { guard mkdirat(deepFD, "d", 0o700) == 0 else { fatalError("deep fixture mkdir") }; let next = openat(deepFD, "d", O_RDONLY | O_DIRECTORY); guard next >= 0 else { fatalError("deep fixture child") }; close(deepFD); deepFD = next; createdLevels += 1 }
      try rejects("512-level tree is rejected by bounded preparation") { _ = try plan(deep) }
      try check(createdLevels == 512, "depth fixture really contains 512 levels without leaking traversal FDs")
    }
    let late = try file("late-race"), retained = root.appendingPathComponent("race-retained"), latePlan = try plan(late)
    latePlan.auditHook = { stage, path in
      if stage == .beforeUnlink { try fm.moveItem(at: path, to: retained); try Data("replacement".utf8).write(to: path) }
    }
    let lateResult = try latePlan.remove()
    print("KNOWN LIMIT: deterministic replacement after the final check is still unlinkable; this is not an atomic deletion guarantee.")
    try check(lateResult.deletedEntries == 1 && !fm.fileExists(atPath: late.path) && (try String(contentsOf: retained)) == "keep", "KNOWN LIMIT reproduced: last-check/unlink gap can delete a replacement; not an atomic identity guarantee")
    print("NetworkDeletionChecks: \(count) assertions passed.")
  }
}
