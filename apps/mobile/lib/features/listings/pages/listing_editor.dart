import 'package:flutter/widgets.dart';
import 'package:uni_stash_mobile/shared/widgets/us_page.dart';
import 'package:uni_stash_mobile/shared/widgets/us_page_header.dart';

class ListingEditor extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return const UsPage(
      header: UsPageHeader(
        title: Text('NEW LISTING'),
        centerTitle: true,
      ),
    );
  }
}
