import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class MyTripsPage extends StatefulWidget {
  const MyTripsPage({super.key});

  @override
  _MyTripsPageState createState() => _MyTripsPageState();
}

class _MyTripsPageState extends State<MyTripsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> tabTitles = [
    "Upcoming Trips",
    "Past Trips",
    "Reserved",
    "Cancelled",
  ];

  final DateFormat _dateTimeFormatter = DateFormat("yyyy-MM-dd hh:mm a");
  final DateFormat _displayFormatter = DateFormat("MMM d, yyyy • h:mm a");
  final DateFormat _displayFormatter2 = DateFormat("MMM d, yyyy");
  String? paymentMethod;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabTitles.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging == false && mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(() {});
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cancelTrip(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(docId)
          .update({'status': 'cancelled'});

      // optional: show snack
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Trip cancelled'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      debugPrint("Error cancelling trip: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error cancelling trip: $e')));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getEnrichedTrips(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> bookingDocs) async {
    final Map<String, List<Map<String, dynamic>>> refsToBookings = {};
    final List<Map<String, dynamic>> directBookings = [];

    for (var doc in bookingDocs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['docId'] = doc.id;
      final String? refStr =
          (data['flightRef'] is String) ? (data['flightRef'] as String) : null;

      if (refStr != null && refStr.trim().isNotEmpty) {
        final key = refStr.startsWith('/') ? refStr.substring(1) : refStr;
        refsToBookings.putIfAbsent(key, () => []).add(data);
      } else {
        directBookings.add(data);
      }
    }

    final Map<String, DocumentSnapshot<Map<String, dynamic>>> fetchedSchedules =
        {};
    if (refsToBookings.isNotEmpty) {
      final futures = refsToBookings.keys.map((path) async {
        try {
          final ref = FirebaseFirestore.instance.doc(path);
          final snap =
              await ref.get() as DocumentSnapshot<Map<String, dynamic>>;
          fetchedSchedules[path] = snap;
        } catch (e) {
          debugPrint("Failed to fetch schedule at $path — $e");
        }
      }).toList();

      await Future.wait(futures);
    }

    DateTime _extractDateFromBooking(Map<String, dynamic> booking) {
      // ROUND-TRIP departure date
      if (booking['departureDate'] != null &&
          booking['departureTime'] != null) {
        try {
          return _dateTimeFormatter.parseLoose(
            "${booking['departureDate']} ${booking['departureTime']}",
          );
        } catch (_) {}
      }

      // ONE-WAY date
      if (booking['flightDate'] != null && booking['flightTime'] != null) {
        try {
          return _dateTimeFormatter.parseLoose(
            "${booking['flightDate']} ${booking['flightTime']}",
          );
        } catch (_) {}
      }

      // fallback
      final ts = booking['timestamp'];
      if (ts is Timestamp) return ts.toDate();

      return DateTime.now();
    }

    final List<Map<String, dynamic>> results = [];

    for (var entry in refsToBookings.entries) {
      final path = entry.key;
      final schedSnap = fetchedSchedules[path]; // may be null
      for (var booking in entry.value) {
        final realDepartureDate = _extractDateFromBooking(booking);

        booking['realDepartureDate'] = realDepartureDate;
        results.add(booking);
      }
    }

    for (var booking in directBookings) {
      final realDepartureDate = _extractDateFromBooking(booking);

      booking['realDepartureDate'] = realDepartureDate;
      results.add(booking);
    }

    return results;
  }

  Future<void> _showPaymentPicker(DateTime reservationDateTime) async {
    if (reservationDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("This reservation is already past. Cannot confirm."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final methods = [
      'GCash',
      'Maya',
      'Debit Card',
      'Credit Card',
      'Cash at Airport'
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: 350,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select Payment Method",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            Expanded(
              child: ListView(
                children: methods
                    .map(
                      (m) => ListTile(
                        title: Text(m),
                        onTap: () => Navigator.pop(ctx, m),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );

    if (selected != null) {
      setState(() => paymentMethod = selected);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Payment successful using $selected"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _payNow(String docId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bookings')
          .doc(docId)
          .get();

      if (!doc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Booking not found."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final data = doc.data()!;
      final String flightDate = data['flightDate'] ?? '';
      final String flightTime = data['flightTime'] ?? '';

      DateTime dep;

      try {
        dep = DateFormat("yyyy-MM-dd hh:mm a").parse("$flightDate $flightTime");
      } catch (_) {
        dep = DateTime.now().add(const Duration(hours: 1));
      }

      if (dep.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("This reservation is already past. Cannot confirm."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      await _showPaymentPicker(dep);

      if (paymentMethod == null) {
        return;
      }

      await FirebaseFirestore.instance
          .collection("bookings")
          .doc(docId)
          .update({
        "paymentMethod": paymentMethod,
        "status": "confirmed",
        "timestamp": FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Reservation confirmed!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _confirmCancel() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Cancel Trip"),
            content: const Text("Are you sure you want to cancel this trip?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false), // user cancels
                child: const Text("No"),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true), // user confirms
                child: const Text(
                  "Yes",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteTrip(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('bookings')
          .doc(docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip deleted'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error deleting trip: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting trip: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _confirmDelete() async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Delete Trip"),
            content: const Text(
                "Are you sure you want to permanently delete this trip?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text("No"),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text(
                  "Yes",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "My Trips",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
            _buildCustomTabToggle(),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('bookings')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text(
                        "No Bookings Found",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    );
                  }

                  return FutureBuilder<List<Map<String, dynamic>>>(
                    future: _getEnrichedTrips(snapshot.data!.docs),
                    builder: (context, enrichedSnapshot) {
                      if (enrichedSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final allTrips = enrichedSnapshot.data ?? [];
                      final filteredTrips = <Map<String, dynamic>>[];
                      final now = DateTime.now();

                      for (var trip in allTrips) {
                        final status =
                            (trip["status"] ?? "").toString().toLowerCase();
                        final DateTime dep =
                            trip['realDepartureDate'] is DateTime
                                ? trip['realDepartureDate']
                                : DateTime.now();

                        switch (_tabController.index) {
                          case 0:
                            if (status == "confirmed" && dep.isAfter(now)) {
                              filteredTrips.add(trip);
                            }
                            break;
                          case 1:
                            if (status == "confirmed" && dep.isBefore(now)) {
                              filteredTrips.add(trip);
                            }
                            break;
                          case 2:
                            if (status == "reserved") filteredTrips.add(trip);
                            break;
                          case 3:
                            if (status == "cancelled") filteredTrips.add(trip);
                            break;
                        }
                      }

                      filteredTrips.sort((a, b) {
                        DateTime dateA =
                            a['realDepartureDate'] ?? DateTime.now();
                        DateTime dateB =
                            b['realDepartureDate'] ?? DateTime.now();
                        if (_tabController.index == 1)
                          return dateB.compareTo(dateA);
                        return dateA.compareTo(dateB);
                      });

                      if (filteredTrips.isEmpty) {
                        String message;
                        switch (_tabController.index) {
                          case 0:
                            message = "No Upcoming Trips";
                            break;
                          case 1:
                            message = "No Past Trips";
                            break;
                          case 2:
                            message = "No Reserved Trips";
                            break;
                          case 3:
                            message = "No Cancelled Trips";
                            break;
                          default:
                            message = "No Trips";
                        }
                        return Center(
                          child: Text(
                            message,
                            style: const TextStyle(
                                fontSize: 18, color: Colors.grey),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: filteredTrips.length,
                        itemBuilder: (context, index) {
                          final trip = filteredTrips[index];
                          final DateTime dep =
                              trip['realDepartureDate'] ?? DateTime.now();
                          final String docId = trip['docId'] ?? '';
                          final bool showCancelButton =
                              (_tabController.index == 0 ||
                                      _tabController.index == 2) &&
                                  dep.isAfter(now);
                          final bool showPayNowButton =
                              _tabController.index == 2 && dep.isAfter(now);
                          final bool isRoundTrip =
                              trip['flightType'] == "Round Trip";

                          final String status =
                              (trip['status'] ?? '').toString();
                          final String origin =
                              (trip['origin'] ?? 'N/A').toString();
                          final String destination =
                              (trip['destination'] ?? 'N/A').toString();
                          final String tClass =
                              (trip['class'] ?? 'Class').toString();
                          final String flightType =
                              (trip['flightType'] ?? 'Flight').toString();

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              height: 150,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Stack(
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Top route
                                      Text(
                                        "$origin → $destination",
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 1),

                                      // Departure row
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.calendar_month,
                                            size: 13,
                                            color: Colors.grey[800],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _displayFormatter.format(dep),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey[800],
                                            ),
                                          ),
                                        ],
                                      ),

                                      // Return route (only if round trip)
                                      if (isRoundTrip &&
                                          trip['returnDate'] != null &&
                                          trip['returnTime'] != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            "$destination → $origin",
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),

                                      // Return date row
                                      if (isRoundTrip &&
                                          trip['returnDate'] != null &&
                                          trip['returnTime'] != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 1),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.refresh,
                                                size: 13,
                                                color: Colors.grey[800],
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                "${_displayFormatter2.format(DateTime.parse(trip['returnDate']))} • ${trip['returnTime']}",
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[800],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      // Flight type & cabin at the bottom
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 1),
                                        child: Text(
                                          "$flightType • $tClass",
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey[800],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (showPayNowButton)
                                          TextButton(
                                            onPressed: () async {
                                              await _payNow(docId);
                                            },
                                            child: Row(
                                              children: [
                                                Icon(Icons.payment,
                                                    color: Colors.blue),
                                                Text(
                                                  "PAY NOW",
                                                  style: TextStyle(
                                                    color: Colors.blue,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if (showCancelButton)
                                          TextButton(
                                            onPressed: () async {
                                              final confirmed =
                                                  await _confirmCancel();
                                              if (confirmed) {
                                                await _cancelTrip(docId);
                                              }
                                            },
                                            child: Row(
                                              children: [
                                                Icon(Icons.cancel,
                                                    color: Colors.red),
                                                Text(
                                                  "CANCEL",
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        if ((_tabController.index == 1 ||
                                            _tabController.index == 3))
                                          TextButton(
                                            onPressed: () async {
                                              final confirmed =
                                                  await _confirmDelete();
                                              if (confirmed) {
                                                await _deleteTrip(docId);
                                              }
                                            },
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete,
                                                    color: Colors.red),
                                                Text(
                                                  "DELETE",
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: status == 'confirmed'
                                            ? Colors.green[100]
                                            : (status == 'cancelled'
                                                ? Colors.red[100]
                                                : Colors.orange[100]),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: status == 'confirmed'
                                              ? Colors.green[800]
                                              : (status == 'cancelled'
                                                  ? Colors.red[800]
                                                  : Colors.orange[800]),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomTabToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(10),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.blue,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.tab,
        tabs: tabTitles.map((title) => Tab(text: title)).toList(),
      ),
    );
  }
}
