
import 'package:flutter/material.dart';
import 'package:lnu_nav_app/components/map/controllers/map.dart';
import 'package:lnu_nav_app/components/map/controllers/zoom.dart';
import 'package:lnu_nav_app/components/ui/future_loading.dart';
import 'package:lnu_nav_app/helpers/data_manager/a-star.dart';
import 'package:lnu_nav_app/store/structure-data.dart';
import 'package:lnu_nav_app/types/pair.dart';
import 'package:lnu_nav_app/types/point.dart';
import 'package:lnu_nav_app/types/structures.dart';
import 'package:provider/provider.dart';
import 'package:lnu_nav_app/components/map/layers/points.dart';
import 'package:lnu_nav_app/components/map/layers/route.dart';
import 'package:lnu_nav_app/components/map/layers/walls.dart';
import 'package:lnu_nav_app/components/map/map.dart';
// geometry
import 'dart:ui' as geom;

class RouteLayout extends StatefulWidget {
  final Pair<Point, Point> route;
  const RouteLayout({
    super.key,
    required this.route,
  });

  @override
  State<RouteLayout> createState() => _RouteLayoutState();
}

enum StairsDirection {
  up,
  down
}

/// Sigle route key
class RoutePointOfInterest {
  final Point point;
  final String title;
  final Widget description;
  final IconData icon;
  final String? kind;

  RoutePointOfInterest({
    required this.point,
    required this.title,
    required this.description,
    required this.icon,
    this.kind
  });

  // generate point of interest

  static RoutePointOfInterest generateStartPoint(Point point) {
    return RoutePointOfInterest(
      point: point,
      title: point.label!,
      description: const Text('Початкова точка'),
      icon: Icons.directions_walk,
    );
  }

  static RoutePointOfInterest generateEndPoint(Point point) {
    return RoutePointOfInterest(
      point: point,
      title: point.label!,
      description: const Text('Кінцева точка'),
      icon: Icons.flag,
    );
  }

  static RoutePointOfInterest generateStairPoint(Point point, StairsDirection direction) {
    final description = direction == StairsDirection.up
        ? 'Підніміться на ${point.z.toInt()} поверх'
        : 'Спустіться на ${point.z.toInt()} поверх';
    // direction
    return RoutePointOfInterest(
        point: point,
        title: 'Сходи',
        description: Text(description),
        icon: Icons.stairs,
        kind: 'stairs'
    );
  }

  static RoutePointOfInterest generateBuildingPoint(Point point, StructureData? structData) {
    final buildingName = structData?.primaryController?.getBuildingById(point.buildingId)?.name;
    final title = buildingName ?? point.label ?? '<Без назви>';
    return RoutePointOfInterest(
      point: point,
      title: title,
      description: const Text('Перехід в іншу будівлю'),
      icon: Icons.home,
    );
  }

  // generate from list
  static List<RoutePointOfInterest> generateFromList(List<Point> points, StructureData structData) {
    final pois = <RoutePointOfInterest>[];

    var previousPoint = points.first;

    for (final point in points) {
      if (point == points.first) {
        pois.add(RoutePointOfInterest.generateStartPoint(point));
      } else if (point == points.last) {
        pois.add(RoutePointOfInterest.generateEndPoint(point));
      }

      // TODO(!important): handle case when both Building and Stairs are present

      // check if z changed -> add stairs on point where Z changed
      else if (point.z != previousPoint.z) {
        final direction = point.z > previousPoint.z
            ? StairsDirection.up
            : StairsDirection.down;
        pois.add(RoutePointOfInterest.generateStairPoint(point, direction));
      }

      // check if building changed -> add building on point where building changed
      else if (point.buildingId != previousPoint.buildingId) {
        pois.add(RoutePointOfInterest.generateBuildingPoint(point, structData));
      }

      previousPoint = point;
    }
    return pois;
  }

}

class RouteData extends ChangeNotifier {
  final List<Point> route;
  final List<RoutePointOfInterest> poi;
  final MapController controller;

  int _currentPoiId = 0;
  int get currentPoiId => _currentPoiId;
  set currentPoiId(int value) {
    if (value < 0 || value >= poi.length) return;
    _currentPoiId = value;
    notifyListeners();
  }


  List<Point> _currentFloorPoints = [];
  List<Point> _currentFloorStairs = [];
  List<Point> get currentFloorPoints => _currentFloorPoints;
  List<Point> get currentFloorStairs => _currentFloorStairs;

  RouteData(this.route, this.poi, this.controller) {
    _updateCurrentFloorPoints();
    controller.addListener(_updateCurrentFloorPoints);
  }

  _updateCurrentFloorPoints() {
    _currentFloorStairs = [];
    final currentFloorId = controller.currentFloor.id;
    final currentBuildingId = controller.currentBuilding.id;
    List<Point> tmp = [];
    var started = false;

    for (var i = 0; i < route.length; i++) {
      final point = route[i];

      if (!started) {
        if (currentPoi.point.id != point.id) continue;
          started = true;
      }

      final onCurrentFloor = point.floorId == currentFloorId;

      // if (onCurrentFloor) {
      //   started = true;
      // }

      if (started) {
        tmp.add(point);

        if (point.kind != null && point.kind!.startsWith('stairs')) {
          _currentFloorStairs.add(point);
        }

        if (!onCurrentFloor) break;
      }
    }
    _currentFloorPoints = tmp.where((point) => point.buildingId == currentBuildingId).toList();
  }

  bool get hasNextPoi => _currentPoiId < poi.length - 1;
  bool get hasPrevPoi => _currentPoiId > 0;

  RoutePointOfInterest get currentPoi => poi[_currentPoiId];

  void gotoNextPoi() {
    if (!hasNextPoi) return;
    _currentPoiId++;
    notifyListeners();
  }

  void gotoPrevPoi() {
    if (!hasPrevPoi) return;
    _currentPoiId--;
    notifyListeners();
  }

  @override
  void dispose() {
    super.dispose();
    controller.removeListener(_updateCurrentFloorPoints);
  }
}

class _RouteLayoutState extends State<RouteLayout> {
  RouteData? route;
  Floor? currentFloor;
  ZoomController zoomController = ZoomController(centerOnStart: false);
  late MapController mapController;

  Future<Pair<List<Point>, List<RoutePointOfInterest>>?> _findPathInternal(StructureData structData) async {
    final route = widget.route;

    final points = structData.graph.points;
    final sp = points[route.first.id];
    final ep = points[route.second.id];

    final path = await AStar(structData.graph).findPath(sp!, ep!);
    if (path == null) return null;

    final poi = RoutePointOfInterest.generateFromList(path, structData);
    return Pair(path, poi);
  }

  Future<Pair<List<Point>, List<RoutePointOfInterest>>?> _findPath() async {
    final structData = Provider.of<StructureData>(context, listen: false);
    // return compute(_findPathInternal, structData);
    return _findPathInternal(structData);
  }

  void changePoi(Point point) {
    zoomController.schedule(scale: 2.0, position: geom.Offset(point.x, point.y));

    final changedFloor = mapController.currentFloor.id != point.floorId;
    final changedBuilding = mapController.currentBuilding.id != point.buildingId;

    if (changedBuilding) {
      mapController.updateCurrentBuilding(buildingId: point.buildingId);
    }

    if (changedFloor) {
      mapController.updateCurrentFloor(floorId: point.floorId);
    }

    if (changedBuilding || changedFloor) {
      mapController.commit();
    }
  }


  @override
  Widget build(BuildContext context) {
    return FutureLoading<List<Point>?>(
      loadingText: 'Пошук маршруту',
      future: _findPath().then((data) {
        if (data == null) return null;
        final path = data.first;
        final startPoint = path.first;
        mapController = MapController.fromContext(
            context: context,
            buildingId: startPoint.buildingId,
            floorId: startPoint.floorId,
            zoomController: zoomController
        );
        route = RouteData(data.first, data.second, mapController);
        changePoi(startPoint);
        return path;
      }),
      builder: (context, path) {
        if (path == null) {
          return const Center(
            child: Text('Failed to build route'),
          );
        }

        return Scaffold(
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: ListenableBuilder(
                  listenable: mapController,
                  builder: (context, _) {
                    final building = mapController.currentBuilding;
                    final floor = mapController.currentFloor;
                    // BreadCrumbs
                    return AppBar(
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(building.name, style: const TextStyle(fontSize: 20)),
                          Text(floor.name, style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                      leading: Center(child: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          route?.dispose();
                          mapController.dispose();
                          Navigator.pop(context);
                        },
                      )),
                      backgroundColor: Colors.black.withAlpha(100),
                    );
                  }),
            ),
            body: Stack(
              children: [
                // Map
                MapWidget(
                  controller: mapController,
                  layers: [
                    WallsLayer(),
                    RouteLayer(route),
                    // CustomPointsLayer(points: route),
                    PointsLayer(),
                  ],
                ),

                // Points of interest
                LayoutBuilder(
                  builder: (context, safeAreaSize) {
                    final safeBottom = MediaQuery.of(context).padding.bottom;
                    final headerHeight = 70 + safeBottom;
                    return Stack(
                      children: [
                        Positioned.fill(
                          child: DraggableScrollableSheet(
                            initialChildSize: headerHeight / safeAreaSize.maxHeight,
                            minChildSize: headerHeight / safeAreaSize.maxHeight,
                            maxChildSize: 0.9,
                            snapSizes: [headerHeight / safeAreaSize.maxHeight, 0.9, 0.5]..sort(),
                            expand: false,

                            snap: true,
                            builder: (context, controller) {
                              if (route == null) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              return Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                    ),
                                  ),
                                  child: ListenableBuilder(
                                    listenable: route!,
                                    builder: (context, _) {
                                      return ListView.builder(
                                        controller: controller,
                                        itemCount: route!.poi.length + 1,
                                        itemBuilder: (context, index) {
                                          // header
                                          if (index == 0) {
                                            // prev button, current point, next button
                                            return Container(
                                              padding: EdgeInsets.fromLTRB(0,0,0, safeBottom),
                                              height: headerHeight,
                                              child: Stack(
                                                children: [
                                                  Column(

                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      const SizedBox(height: 10),
                                                      Center(
                                                        child: Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                                                          children: [
                                                            const SizedBox(width: 20),
                                                            IconButton(
                                                                icon: const Icon(Icons.arrow_back),
                                                                onPressed: !route!.hasPrevPoi
                                                                    ? null
                                                                    : () {
                                                                  route!.gotoPrevPoi();
                                                                  changePoi(route!.currentPoi.point);
                                                                }
                                                            ),
                                                            // Text(route!.currentPoi.title),
                                                            // fit onl
                                                            // wrap text into box with max height to prevent overflow
                                                            Flexible(
                                                              child: Container(
                                                                constraints: const BoxConstraints(
                                                                  maxHeight: 40,
                                                                ),
                                                                child: Center(
                                                                  child: Text(
                                                                    route!.currentPoi.title,
                                                                    overflow: TextOverflow.ellipsis,
                                                                    textAlign: TextAlign.center,
                                                                    maxLines: 2,
                                                                    style: const TextStyle(
                                                                      fontSize: 16,
                                                                      fontWeight: FontWeight.w600,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),

                                                            IconButton(
                                                                icon: const Icon(Icons.arrow_forward),
                                                                onPressed: !route!.hasNextPoi
                                                                    ? null
                                                                    : () {
                                                                  route!.gotoNextPoi();
                                                                  changePoi(route!.currentPoi.point);
                                                                }
                                                            ),
                                                            const SizedBox(width: 20),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  // drag handle
                                                  Positioned(
                                                    top: 10,
                                                    left: 0,
                                                    right: 0,
                                                    child: Center(
                                                      child: Container(
                                                        width: 50,
                                                        height: 5,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withOpacity(0.3),
                                                          borderRadius: BorderRadius.circular(10),
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                ],
                                              )
                                            );
                                          }

                                          final pointIndex = index - 1;
                                          final point = route!.poi[pointIndex];
                                          return ListTile(
                                            title: Text(point.title),
                                            subtitle: point.description,
                                            leading: Icon(point.icon),
                                            selected: route!._currentPoiId == pointIndex,
                                            tileColor: route!._currentPoiId < index
                                                ? Colors.black.withAlpha(100)
                                                : null,

                                            onTap: () {
                                              if (route!._currentPoiId == pointIndex) return;
                                              route!.currentPoiId = pointIndex;
                                              changePoi(route!.currentPoi.point);
                                            },
                                          );
                                        },
                                      );
                                    },
                                  )
                              );
                            },
                          )
                        ),
                      ],
                    );
                  },
                )
              ],
            )
        );

      },
    );
  }
}