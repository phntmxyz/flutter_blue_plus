import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_example/widgets/descriptor_tile.dart';
import 'package:flutter_blue_plus_example/widgets/get_services_button.dart';

import "characteristic_tile.dart";

class ServiceTile extends StatelessWidget {
  final BluetoothService service;
  final List<CharacteristicTile> characteristicTiles;

  const ServiceTile({super.key, required this.service, required this.characteristicTiles});

  Widget buildUuid(BuildContext context) {
    String uuid = '0x${service.uuid.str.toUpperCase()}';
    return Text(uuid, style: TextStyle(fontSize: 13));
  }

  @override
  Widget build(BuildContext context) {
    return characteristicTiles.isNotEmpty
        ? ExpansionTile(
            title: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Service', style: TextStyle(color: Theme.of(context).primaryColor)),
                buildUuid(context),
              ],
            ),
            children: characteristicTiles,
          )
        : ListTile(
            title: const Text('Service'),
            subtitle: buildUuid(context),
          );
  }
}

class ServicesSection extends StatelessWidget {
  const ServicesSection({
    super.key,
    this.isDiscoveringServices = false,
    this.onDiscoverServicesPressed,
    this.services = const [],
  });

  final List<BluetoothService> services;

  final bool isDiscoveringServices;
  final void Function()? onDiscoverServicesPressed;

  @override
  Widget build(BuildContext context) {
    return services.isNotEmpty
        ? ExpansionTile(
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Services (${services.length})',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Transform.translate(
                  offset: const Offset(0, 5),
                  child: GetServicesButton(
                    isDiscovering: isDiscoveringServices,
                    onTap: onDiscoverServicesPressed,
                  ),
                )
              ],
            ),
            children: services.map((s) {
              return ServiceTile(
                service: s,
                characteristicTiles: s.characteristics
                    .map((c) => CharacteristicTile(
                          characteristic: c,
                          descriptorTiles: c.descriptors.map((d) => DescriptorTile(descriptor: d)).toList(),
                        ))
                    .toList(),
              );
            }).toList(),
          )
        : ListTile(
            title: const Text('Services (0)'),
            trailing: GetServicesButton(
              isDiscovering: isDiscoveringServices,
              onTap: onDiscoverServicesPressed,
            ),
          );
  }
}
