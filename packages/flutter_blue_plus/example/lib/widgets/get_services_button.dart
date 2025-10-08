import 'package:flutter/material.dart';

class GetServicesButton extends StatelessWidget {
  const GetServicesButton({super.key, this.isDiscovering = false, this.onTap});

  final bool isDiscovering;
  final void Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: isDiscovering ? 1 : 0,
      children: <Widget>[
        TextButton(
          onPressed: onTap,
          child: const Text("Refresh Services"),
        ),
        const IconButton(
          icon: SizedBox(
            width: 18.0,
            height: 18.0,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Colors.grey),
            ),
          ),
          onPressed: null,
        )
      ],
    );
  }
}
