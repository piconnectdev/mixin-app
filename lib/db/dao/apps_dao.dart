import 'package:moor/moor.dart';

import '../mixin_database.dart';

part 'apps_dao.g.dart';

@UseDao(tables: [Apps])
class AppsDao extends DatabaseAccessor<MixinDatabase> with _$AppsDaoMixin {
  AppsDao(MixinDatabase db) : super(db);

  Future<int> insert(App app) => into(db.apps).insertOnConflictUpdate(app);

  Future deleteApp(App app) => delete(db.apps).delete(app);
}
