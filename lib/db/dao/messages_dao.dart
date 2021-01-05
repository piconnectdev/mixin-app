import 'package:flutter_app/db/mixin_database.dart';
import 'package:moor/moor.dart';

part 'messages_dao.g.dart';

@UseDao(tables: [Messages])
class MessagesDao extends DatabaseAccessor<MixinDatabase>
    with _$MessagesDaoMixin {
  MessagesDao(MixinDatabase db) : super(db);

  Future<int> insert(Message message) => into(db.messages).insert(message);

  Future deleteMessage(Message message) => delete(db.messages).delete(message);
}
