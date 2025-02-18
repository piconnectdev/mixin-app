import 'package:drift/drift.dart';

import '../mixin_database.dart';

part 'participant_session_dao.g.dart';

@DriftAccessor()
class ParticipantSessionDao extends DatabaseAccessor<MixinDatabase>
    with _$ParticipantSessionDaoMixin {
  ParticipantSessionDao(super.db);

  Future<int> insert(ParticipantSessionData participantSession) =>
      into(db.participantSession)
          .insert(participantSession, mode: InsertMode.insertOrReplace);

  Future<ParticipantSessionKey?> getParticipantSessionKeyWithoutSelf(
          String conversationId, String userId) =>
      db
          .participantSessionKeyWithoutSelf(conversationId, userId)
          .getSingleOrNull();

  Future<ParticipantSessionKey?> getOtherParticipantSessionKey(
          String conversationId, String userId, String sessionId) =>
      db
          .otherParticipantSessionKey(conversationId, userId, sessionId)
          .getSingleOrNull();

  Future deleteByStatus(String conversationId) async {
    await (delete(db.participantSession)
          ..where((tbl) =>
              tbl.conversationId.equals(conversationId) &
              tbl.sentToServer.equals(1).not()))
        .go();
  }

  Future deleteByConversationId(String conversationId) async {
    await (delete(db.participantSession)
          ..where((tbl) => tbl.conversationId.equals(conversationId)))
        .go();
  }

  Future deleteByCIdAndPId(String conversationId, String participantId) async =>
      (delete(db.participantSession)
            ..where((tbl) =>
                tbl.conversationId.equals(conversationId) &
                tbl.userId.equals(participantId)))
          .go();

  Future emptyStatusByConversationId(String conversationId) async =>
      (update(db.participantSession)
            ..where((tbl) => tbl.conversationId.equals(conversationId)))
          .write(const ParticipantSessionCompanion(sentToServer: Value(null)));

  Future<List<ParticipantSessionData>> getParticipantSessionsByConversationId(
          String conversationId) async =>
      (select(db.participantSession)
            ..where((tbl) => tbl.conversationId.equals(conversationId)))
          .get();

  Future insertAll(List<ParticipantSessionData> list) async {
    await batch((batch) => batch.insertAll(db.participantSession, list,
        mode: InsertMode.insertOrReplace));
  }

  Future deleteList(List<ParticipantSessionData> list) async {
    for (final p in list) {
      await delete(db.participantSession).delete(p);
    }
  }

  Future replaceAll(
          String conversationId, List<ParticipantSessionData> list) async =>
      transaction(() async {
        await deleteByConversationId(conversationId);
        await insertAll(list);
      });

  Future<List<ParticipantSessionData>> getNotSendSessionParticipants(
          String conversationId, String sessionId) async =>
      db.notSendSessionParticipants(conversationId, sessionId).get();

  Future<ParticipantSessionData?> getParticipantSessionKeyBySessionId(
          String conversationId, String sessionId) async =>
      db
          .participantSessionKeyBySessionId(conversationId, sessionId)
          .getSingleOrNull();

  Future updateList(List<ParticipantSessionData> list) async {
    for (final p in list) {
      await update(db.participantSession).replace(p);
    }
  }

  Future<void> deleteBySessionId(String sessionId) async {
    await (delete(db.participantSession)
          ..where((t) => t.sessionId.equals(sessionId)))
        .go();
  }

  Future<void> updateSentToServer() async {
    await update(db.participantSession)
        .write(const ParticipantSessionCompanion(sentToServer: Value(null)));
  }
}
