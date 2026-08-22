//
//  KMPTaskHabitPorts.swift
//  Deadliner
//
//  UID-first contracts for the KMP-owned Task and Habit aggregates.
//

#if canImport(Shared)
import Shared

typealias KMPTask = Task_
typealias KMPHabit = Habit_
typealias KMPHabitRecord = Shared.HabitRecord

protocol KMPTaskPersistenceStore: Sendable {
    func allTasks() async -> [KMPTask]
    func task(uid: String) async -> KMPTask?
    func create(_ task: KMPTask) async
    func update(_ task: KMPTask) async
    func delete(uid: String, updatedAt: String) async
}

protocol KMPHabitPersistenceStore: Sendable {
    func allHabits() async -> [KMPHabit]
    func habit(uid: String) async -> KMPHabit?
    func records(habitUID: String) async -> [KMPHabitRecord]
    func create(_ habit: KMPHabit) async
    func update(_ habit: KMPHabit) async
    func delete(uid: String, updatedAt: String) async
    func save(record: KMPHabitRecord) async
}
#endif
