import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class BookRoundTripPage extends StatefulWidget {
  final String route;

  const BookRoundTripPage({super.key, required this.route});

  @override
  State<BookRoundTripPage> createState() => _RoundTripBookingPageState();
}

class _RoundTripBookingPageState extends State<BookRoundTripPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- STATE VARIABLES ---
  String? originCity;
  String? destinationCity;

  int adultCount = 1;
  int childCount = 0;
  int infantCount = 0;
  int personWithDisabilityCount = 0;
  int ofwCount = 0;
  int seniorCitizenCount = 0;

  // Selected flights
  String? selectedDepartureFlightId;
  String? selectedReturnFlightId;
  double? departureFlightPrice;
  double? returnFlightPrice;
  int maxDepartureSeats = 0;
  int maxReturnSeats = 0;

  String flightClass = 'Economy';
  DateTime? departureDate;
  DateTime? returnDate;
  bool _isBooking = false;

  // Payment
  String? paymentMethod;

  int get totalPassengers =>
      adultCount +
      childCount +
      infantCount +
      personWithDisabilityCount +
      ofwCount +
      seniorCitizenCount;

  @override
  void initState() {
    super.initState();
    if (widget.route.isNotEmpty) {
      List<String> parts = widget.route.split('-to-');
      if (parts.length == 2) {
        originCity = parts[0];
        destinationCity = parts[1];
      }
    }
  }

  // --- COLLECTIONS ---
  CollectionReference getDepartureFlightsCollection() {
    String currentRoute = '${originCity ?? ""}-to-${destinationCity ?? ""}';
    return _firestore
        .collection('flightbooking')
        .doc('all-round-trip-schedules')
        .collection(currentRoute);
  }

  CollectionReference getReturnFlightsCollection() {
    String currentRoute = '${originCity ?? ""}-to-${destinationCity ?? ""}';
    return _firestore
        .collection('flightbooking')
        .doc('all-round-trip-schedules')
        .collection(currentRoute);
  }

  // --- FLIGHT SELECTION ---
  void selectDepartureFlight(String docId, int seats, double price) {
    setState(() {
      selectedDepartureFlightId = docId;
      maxDepartureSeats = seats;
      departureFlightPrice = price;
    });
  }

  void selectReturnFlight(String docId, int seats, double price) {
    setState(() {
      selectedReturnFlightId = docId;
      maxReturnSeats = seats;
      returnFlightPrice = price;
    });
  }

  // --- DATE PICKERS ---
  Future<void> _pickDepartureDate() async {
    DateTime now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: departureDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => departureDate = picked);
  }

  Future<void> _pickReturnDate() async {
    DateTime now = DateTime.now();
    // default initial date: either current returnDate or tomorrow
    final initialDate =
        returnDate ?? departureDate?.add(const Duration(days: 1)) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: departureDate != null
          ? departureDate!.add(const Duration(days: 1))
          : now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => returnDate = picked);
    }
  }

  // --- CITY PICKER ---
  Future<void> _showCityPicker(bool isOrigin) async {
    final cityMap = {
      'Manila (MNL)': 'MNL',
      'Cebu (CEBU)': 'CEBU',
      'Davao (DVO)': 'DVO',
      'Boracay (MPH)': 'MPH',
      'Palawan (PPS)': 'PPS',
      'Bicol (BKO)': 'BKO',
      'Zamboanga (ZAM)': 'ZAM',
      'Iloilo (ILO)': 'ILO',
    };

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        height: 300,
        child: ListView(
          children: cityMap.entries
              .map((entry) => ListTile(
                    title: Text(entry.key),
                    onTap: () => Navigator.pop(ctx, entry.value),
                  ))
              .toList(),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        if (isOrigin) {
          originCity = selected;
          if (destinationCity == originCity) destinationCity = null;
        } else {
          destinationCity = selected;
        }
        selectedDepartureFlightId = null;
        selectedReturnFlightId = null;
        maxDepartureSeats = 0;
        maxReturnSeats = 0;
        paymentMethod = null;
      });
    }
  }

  // --- PAYMENT ---
  Future<void> _showPaymentPicker() async {
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
                    .map((m) => ListTile(
                          title: Text(m),
                          onTap: () => Navigator.pop(ctx, m),
                        ))
                    .toList(),
              ),
            )
          ],
        ),
      ),
    );

    if (selected != null) setState(() => paymentMethod = selected);
  }

  // --- PASSENGER PICKER ---
  Future<void> _showPassengerPicker() async {
    int tempAdult = adultCount;
    int tempChild = childCount;
    int tempInfant = infantCount;
    int tempPWD = personWithDisabilityCount;
    int tempOFW = ofwCount;
    int tempSenior = seniorCitizenCount;
    int maxSeats = 9; // Maximum seats excluding infants

    Widget buildRow(String label, String sub, int count, Function(int) onChange,
        {bool isInfant = false}) {
      int currentTotalExclInfant =
          tempAdult + tempChild + tempPWD + tempOFW + tempSenior;

      bool isIncDisabled;
      if (isInfant) {
        isIncDisabled = count >= currentTotalExclInfant;
      } else {
        isIncDisabled = currentTotalExclInfant >= maxSeats;
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (sub.isNotEmpty)
                    Text(sub,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12))
                ])),
            IconButton(
                onPressed: count <= 0 ? null : () => onChange(count - 1),
                icon: Icon(Icons.remove_circle_outline,
                    color: count <= 0 ? Colors.grey : Colors.blue)),
            SizedBox(
                width: 20,
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold))),
            IconButton(
                onPressed: isIncDisabled ? null : () => onChange(count + 1),
                icon: Icon(Icons.add_circle_outline,
                    color: isIncDisabled ? Colors.grey : Colors.blue)),
          ],
        ),
      );
    }

    final result = await showModalBottomSheet<Map<String, int>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) => Container(
          padding: const EdgeInsets.all(20),
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Select Passengers',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx))
              ]),
              const Divider(),
              Expanded(
                  child: SingleChildScrollView(
                child: Column(children: [
                  buildRow('Adult', '12 y +', tempAdult,
                      (v) => setModal(() => tempAdult = v)),
                  buildRow('Child', '2 y - 11 y', tempChild,
                      (v) => setModal(() => tempChild = v)),
                  buildRow('Person with Disability', '', tempPWD,
                      (v) => setModal(() => tempPWD = v)),
                  buildRow('Infant', '16 d - 23 m', tempInfant,
                      (v) => setModal(() => tempInfant = v),
                      isInfant: true),
                  buildRow('Overseas Filipino Worker', '', tempOFW,
                      (v) => setModal(() => tempOFW = v)),
                  buildRow('Senior Citizen', '60 y +', tempSenior,
                      (v) => setModal(() => tempSenior = v)),
                ]),
              )),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, {
                        'adult': tempAdult,
                        'child': tempChild,
                        'pwd': tempPWD,
                        'infant': tempInfant,
                        'ofw': tempOFW,
                        'senior': tempSenior
                      }),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Continue',
                      style: TextStyle(color: Colors.white)))
            ],
          ),
        ),
      ),
    );

    if (result != null) {
      setState(() {
        adultCount = result['adult']!;
        childCount = result['child']!;
        personWithDisabilityCount = result['pwd']!;
        infantCount = result['infant']!;
        ofwCount = result['ofw']!;
        seniorCitizenCount = result['senior']!;
      });
    }
  }

  // --- CLASS PICKER ---
  Future<void> _showClassPicker() async {
    String tempClass = flightClass;
    final classes = [
      'All Cabin',
      'Economy',
      'Comfort',
      'Premium Economy',
      'Business'
    ];

    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setModal) => Container(
          padding: const EdgeInsets.all(20),
          height: 350,
          child: Column(
            children: [
              const Text('Select Cabin',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Divider(),
              Expanded(
                  child: ListView(
                children: classes
                    .map((c) => RadioListTile(
                        title: Text(c),
                        value: c,
                        groupValue: tempClass,
                        activeColor: Colors.blue,
                        onChanged: (v) => setModal(() => tempClass = v!)))
                    .toList(),
              )),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, tempClass),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      minimumSize: const Size(double.infinity, 50)),
                  child: const Text('Continue',
                      style: TextStyle(color: Colors.white))),
            ],
          ),
        ),
      ),
    );

    if (selected != null) setState(() => flightClass = selected);
  }

  // --- BOOKING LOGIC ---
  Future<void> handleRoundTripBooking(String status, String method) async {
    if (selectedDepartureFlightId == null ||
        selectedReturnFlightId == null ||
        totalPassengers <= 0 ||
        paymentMethod == null) return;

    setState(() => _isBooking = true);

    final departureRef =
        getDepartureFlightsCollection().doc(selectedDepartureFlightId);
    final returnRef = getReturnFlightsCollection().doc(selectedReturnFlightId);

    try {
      await _firestore.runTransaction((transaction) async {
        final depSnap = await transaction.get(departureRef);
        final retSnap = await transaction.get(returnRef);
        if (!depSnap.exists || !retSnap.exists)
          throw Exception("Flight not found");

        final depData = depSnap.data() as Map<String, dynamic>;
        final retData = retSnap.data() as Map<String, dynamic>;

        String depDate = DateFormat('yyyy-MM-dd')
            .format((depData['date'] as Timestamp).toDate());
        String retDate = DateFormat('yyyy-MM-dd')
            .format((retData['date'] as Timestamp).toDate());

        transaction.set(_firestore.collection('bookings').doc(), {
          "departureFlightRef": departureRef,
          "returnFlightRef": returnRef,
          "status": status,
          "flightType": "Round Trip",
          "origin": originCity,
          "destination": destinationCity,
          "departureDate": depDate,
          "returnDate": retDate,
          "departureTime": depData['time'],
          "returnTime": retData['time'],
          "totalPassengers": totalPassengers,
          "paymentMethod": paymentMethod,
          "passengerDetails": {
            'adult': adultCount,
            'child': childCount,
            'disability': personWithDisabilityCount,
            'infant': infantCount,
            'ofw': ofwCount,
            'senior': seniorCitizenCount
          },
          "class": flightClass,
          "totalPrice": totalPassengers *
              ((depData['price'] ?? 0) + (retData['price'] ?? 0)),
          "timestamp": FieldValue.serverTimestamp(),
        });

        transaction.update(departureRef,
            {"seatAvailable": depData['seatAvailable'] - totalPassengers});
        transaction.update(returnRef,
            {"seatAvailable": retData['seatAvailable'] - totalPassengers});
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'confirmed'
              ? "Booking Confirmed!"
              : "Flight Reserved!")));

      setState(() {
        selectedDepartureFlightId = null;
        selectedReturnFlightId = null;
        maxDepartureSeats = 0;
        maxReturnSeats = 0;
        paymentMethod = null;
        adultCount = 1;
        childCount = 0;
        infantCount = 0;
        personWithDisabilityCount = 0;
        ofwCount = 0;
        seniorCitizenCount = 0;
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed: $e")));
    } finally {
      setState(() => _isBooking = false);
    }
  }

  // --- UI HELPERS ---
  Widget _buildLocationInput(
      {required String label,
      required String? code,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          Text(code ?? "Select",
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: code == null ? Colors.grey : Colors.blue))
        ]),
      ),
    );
  }

  Widget _buildSelector(String label, String val, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          const SizedBox(height: 4),
          Text(val,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String depDateStr = departureDate == null
        ? "Select Date"
        : DateFormat('dd MMM yyyy').format(departureDate!);
    String retDateStr = returnDate == null
        ? "Select Date"
        : DateFormat('dd MMM yyyy').format(returnDate!);

    bool canProceed = selectedDepartureFlightId != null &&
        selectedReturnFlightId != null &&
        totalPassengers > 0 &&
        paymentMethod != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 20),
        // LOCATION CARD
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                    child: _buildLocationInput(
                        label: "From",
                        code: originCity,
                        onTap: () => _showCityPicker(true))),
                IconButton(
                  icon: const Icon(Icons.swap_horiz, color: Colors.blue),
                  onPressed: () {
                    if (originCity != null && destinationCity != null) {
                      setState(() {
                        String temp = originCity!;
                        originCity = destinationCity;
                        destinationCity = temp;
                        selectedDepartureFlightId = null;
                        selectedReturnFlightId = null;
                        maxDepartureSeats = 0;
                        maxReturnSeats = 0;
                        paymentMethod = null;
                      });
                    }
                  },
                ),
                Expanded(
                    child: _buildLocationInput(
                        label: "To",
                        code: destinationCity,
                        onTap: () => _showCityPicker(false))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // DEPARTURE DATE
        InkWell(
          onTap: _pickDepartureDate,
          child: Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.blue),
                  const SizedBox(width: 10),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Departure Date",
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                        Text(depDateStr,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ])
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // RETURN DATE
        InkWell(
          onTap: _pickReturnDate,
          child: Card(
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: Colors.blue),
                  const SizedBox(width: 10),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Return Date",
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                        Text(retDateStr,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ])
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        // PASSENGERS & CLASS
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                    child: _buildSelector("Passengers", "$totalPassengers",
                        _showPassengerPicker)),
                const VerticalDivider(
                    color: Colors.transparent,
                    thickness: 1,
                    indent: 10,
                    endIndent: 10),
                Expanded(
                    child:
                        _buildSelector("Class", flightClass, _showClassPicker)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // PAYMENT METHOD
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: InkWell(
            onTap: _showPaymentPicker,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.payment, color: Colors.blue),
                  const SizedBox(width: 10),
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Payment Method",
                            style: TextStyle(
                                color: Colors.grey.shade600, fontSize: 12)),
                        Text(paymentMethod ?? "Select Payment Method",
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                      ])
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),
        // DEPARTURE FLIGHTS
        if (originCity != null &&
            destinationCity != null &&
            departureDate != null) ...[
          const Text("Available Departure Flights:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: getDepartureFlightsCollection().snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final docs = snapshot.data!.docs;
              if (docs.isEmpty)
                return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("No departure flights found."));
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  bool isSel = docs[i].id == selectedDepartureFlightId;
                  double price = (data['price'] ?? 0).toDouble();
                  DateTime flightDate = (data['date'] as Timestamp).toDate();
                  if (flightDate.day != departureDate!.day ||
                      flightDate.month != departureDate!.month) {
                    return const SizedBox.shrink();
                  }
                  return Card(
                    color: isSel ? Colors.blue.shade50 : Colors.white,
                    shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: isSel ? Colors.blue : Colors.transparent),
                        borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      onTap: () => selectDepartureFlight(
                          docs[i].id, data['seatAvailable'] ?? 0, price),
                      title: Text("${data['time']} - ₱$price",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Seats: ${data['seatAvailable']}"),
                      trailing: isSel
                          ? const Icon(Icons.check_circle, color: Colors.blue)
                          : const Text("Select"),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
        ],
        // RETURN FLIGHTS
        if (originCity != null &&
            destinationCity != null &&
            returnDate != null) ...[
          const Text("Available Return Flights:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: getReturnFlightsCollection().snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const LinearProgressIndicator();
              final docs = snapshot.data!.docs;
              if (docs.isEmpty)
                return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text("No return flights found."));
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  bool isSel = docs[i].id == selectedReturnFlightId;
                  double price = (data['price'] ?? 0).toDouble();
                  DateTime flightDate = (data['date'] as Timestamp).toDate();
                  if (flightDate.day != returnDate!.day ||
                      flightDate.month != returnDate!.month) {
                    return const SizedBox.shrink();
                  }
                  return Card(
                    color: isSel ? Colors.blue.shade50 : Colors.white,
                    shape: RoundedRectangleBorder(
                        side: BorderSide(
                            color: isSel ? Colors.blue : Colors.transparent),
                        borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      onTap: () => selectReturnFlight(
                          docs[i].id, data['seatAvailable'] ?? 0, price),
                      title: Text("${data['time']} - ₱$price",
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("Seats: ${data['seatAvailable']}"),
                      trailing: isSel
                          ? const Icon(Icons.check_circle, color: Colors.blue)
                          : const Text("Select"),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 20),
        ],
        // BOOK / RESERVE BUTTONS
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: (canProceed && !_isBooking)
                  ? () => handleRoundTripBooking('reserved', paymentMethod!)
                  : null,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Colors.blue, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: _isBooking
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator())
                  : const Text("RESERVE",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.blue)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: (canProceed && !_isBooking)
                  ? () => handleRoundTripBooking('confirmed', paymentMethod!)
                  : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 5),
              child: _isBooking
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white))
                  : const Text("BOOK NOW",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
        const SizedBox(height: 20),
      ]),
    );
  }
}
