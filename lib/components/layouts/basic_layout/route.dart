import 'dart:isolate';

import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lnu_nav_app/components/layouts/basic_layout/route/point-input.dart';
import 'package:lnu_nav_app/components/layouts/route_layout/layout.dart';
import 'package:lnu_nav_app/extensions/hex_color.dart';
import 'package:lnu_nav_app/helpers/converter.dart';
import 'package:lnu_nav_app/helpers/data_manager/a-star.dart';
import 'package:lnu_nav_app/helpers/simplify-string.dart';
import 'package:lnu_nav_app/store/structure-data.dart';
import 'package:lnu_nav_app/types/pair.dart';
import 'package:lnu_nav_app/variables.dart';
import 'package:lnu_nav_app/types/point.dart';
import 'package:provider/provider.dart';

enum CurrentPoint {
  start,
  end,
  none,
}

class RouteForm extends StatefulWidget {
  const RouteForm({
    Key? key,
  }) : super(key: key);

  @override
  State<RouteForm> createState() => _RouteFormState();
}

class _RouteFormState extends State<RouteForm> {
  late PointInputController _startPointController;
  late PointInputController _endPointController;
  late ValueNotifier<CurrentPoint> currentPoint = ValueNotifier(CurrentPoint.none);

  ValueNotifier<List<Pair<Point, double>>> foundPoints = ValueNotifier([]);

  // set current point based on focused input
  get selectedPointText {
    if (currentPoint.value == CurrentPoint.start) {
      return _startPointController;
    } else if (currentPoint.value == CurrentPoint.end) {
      return _endPointController.text;
    } else {
      return '';
    }
  }

  @override
  void initState() {
    _startPointController = PointInputController(
      onChange: onTextChange,
      onFocusChange: (focused) {
        if (focused) {
          currentPoint.value = CurrentPoint.start;
        } else if (currentPoint.value == CurrentPoint.start) {
          currentPoint.value = CurrentPoint.none;
        }
      }
    );
    _endPointController = PointInputController(
      onChange: onTextChange,
      onFocusChange: (focused) => setState(() {
        if (focused) {
          currentPoint.value = CurrentPoint.end;
        } else if (currentPoint.value == CurrentPoint.end) {
          currentPoint.value = CurrentPoint.none;
        }
      }),
    );

    super.initState();
  }

  Future<List<Pair<Point, double>>> _searchResults(StructureData structData, String search, Point? startPoint) async {
    if (currentPoint.value == CurrentPoint.start || startPoint == null) {
      if (simplifyString(search).isEmpty) return [];

      return structData.primaryController!.labeledPoints
          .where((point) => simplifyString(point.label!).contains(simplifyString(search)))
          .map((point) => Pair(point, 0.0))
          .toList();
    } else {
      return await AStar(structData.graph).findClosestPointsAsync(startPoint, search: search, amount: 10);
    }
  }

  onTextChange(String search) async {
    final startPoint = _startPointController.selectedPoint;

    if (search.isEmpty && startPoint == null) {
      foundPoints.value = [];
      return;
    }
    final structData = Provider.of<StructureData>(context, listen: false);
    final results = await _searchResults(structData, search, startPoint);
    foundPoints.value = results.sublist(0, math.min(10, results.length));
  }

//  MaterialButton(
//                   onPressed: () {},
//                   color: inputBackgroundColor,
//                   shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(10)),
//                   child: const Icon(Icons.location_searching,
//                       color: Colors.white)),

  @override
  Widget build(BuildContext context) {
    final white = Colors.white.withOpacity(.7);
    final chevronRight = Icon(Icons.chevron_right, color: white);

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Маршрут'),
              centerTitle: true,
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PointInput(
                controller: _startPointController,
                icon: (controller) => SvgPicture.asset(
                  'assets/icons/MapPin.svg',
                  color:  controller.selectedPoint == null
                      ? Colors.white
                      : purpleColor.withOpacity(0.8),
                  width: 25,
                  height: 25,
                ),
                hintText: 'Початкова точка',
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PointInput(
                controller: _endPointController,
                icon: (controller) => SvgPicture.asset(
                  'assets/icons/MapPin.svg',
                  color: controller.selectedPoint == null
                      ? Colors.white
                      : purpleColor.withOpacity(0.8),
                  width: 25,
                  height: 25,
                ),
                hintText: 'Кінцева точка',
              ),
            ),

            Expanded(
              child: ListenableBuilder(listenable: Listenable.merge([
                foundPoints,
                currentPoint,
              ]), builder: (context, _) {
                if (currentPoint.value == CurrentPoint.none) {
                  final hasStart = _startPointController.selectedPoint != null;
                  final hasEnd = _endPointController.selectedPoint != null;

                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child: Builder(builder: (context) {
                          if (hasStart && hasEnd) {
                            return const Text('Натисніть на кнопку для пошуку маршруту');
                          } else if (hasStart) {
                            return const Text('Виберіть кінцеву точку');
                          } else {
                            return const Text('Виберіть початкову точку');
                          }
                        })
                    ),
                  );
                }

                return Consumer<StructureData>(
                  builder: (context, structData, _) {
                    return ListView.builder(
                        padding: const EdgeInsets.all(0),
                        clipBehavior: Clip.hardEdge,
                        physics: const BouncingScrollPhysics(),
                        itemCount: foundPoints.value.length,
                        itemBuilder: (context, index) {
                          final data = foundPoints.value[index];
                          final point = data.first;
                          final distance = data.second;

                          final isEndPoint = currentPoint.value == CurrentPoint.end;

                          final time = isEndPoint
                              ? remainTime(metersToTime(coordsToMeters(distance)))
                              : null;

                          return ListTile(
                            onTap: () {
                              if (currentPoint.value == CurrentPoint.none) return;

                              final pc = currentPoint.value == CurrentPoint.start
                                  ? _startPointController
                                  : _endPointController;

                              pc.textEditingController.text = point.label!;
                              pc.focusController.unfocus();
                              pc.selectPoint(point);
                            },
                            leading: Builder(builder: (context) {
                              final kind = point.kind;
                              final color = point.color != null
                                  ? HexColor.fromHex(point.color!) ?? purpleColor
                                  : purpleColor;
                              // kinds: point, wc, stairs_up, stairs_down
                              // if no kind -> room

                              Widget icon = SvgPicture.asset(
                                'assets/icons/MapPin.svg',
                                color: color,
                                width: 40,
                                height: 40,
                              );

                              switch (kind) {
                                case 'wc':
                                  icon = SvgPicture.asset(
                                    'assets/icons/WC.svg',
                                    color: color,
                                    width: 35,
                                    height: 35,
                                  );
                                  break;
                                case 'stairs_up':
                                case 'stairs_down':
                                  icon = Icon(Icons.stairs, color: color, size: 25);
                                  break;
                              }

                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  icon,
                                ],
                              );
                            }),
                            title: Text(point.label!),
                            // isThreeLine: time != null,
                            // floor / building if not default
                            subtitle: Builder(builder: (context) {
                              final children = <Widget>[];
                              final controller = structData.primaryController!;
                              final building = controller.getBuildingById(point.buildingId);
                              if (building != null) {
                                children.add(Text(building.name, style: TextStyle(color: white)));

                                final floor = controller.getFloorById(
                                    point.buildingId, point.floorId);
                                if (floor != null) {
                                  children.add(chevronRight);
                                  children.add(Text(floor.name, style: TextStyle(color: white)));
                                }
                              }

                              if (time != null) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: children,
                                    ),
                                    Row(
                                      children: [
                                        Icon(Icons.timer, color: white, size: 15),
                                        const SizedBox(width: 5),
                                        Text(time, style: TextStyle(color: white)),
                                      ],
                                    )
                                  ],
                                );
                              }

                              return Row(children: children);
                            }),
                          );
                        });
                  },
                );
              }),
            )
          ],
        ),
        ListenableBuilder(listenable: Listenable.merge([
          _startPointController,
          _endPointController,
        ]), builder: (context, _) {
          final startPoint = _startPointController.selectedPoint;
          final endPoint = _endPointController.selectedPoint;

          if (startPoint == null || endPoint == null) return const SizedBox(height: 0);

          return Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              backgroundColor: purpleColor,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => RouteLayout(route: Pair(
                    startPoint,
                    endPoint,
                  )))
                );
              },
              child: const Icon(Icons.search, color: Colors.white),
            ),
          );
        })
      ],
    );
  }
}


