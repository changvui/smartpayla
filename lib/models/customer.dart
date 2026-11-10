class Customer {
  final String id;
  final String name;
  final String phone;
  final String address;

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
  });

  Map<String, dynamic> toMap() {
    return {
      'customerName': name,
      'phoneNumber': phone,
      'address': address,
    };
  }

  factory Customer.fromMap(String id, Map<String, dynamic> map) {
    return Customer(
      id: id,
      name: map['customerName'] ?? 'Unknown',
      phone: map['phoneNumber'] ?? 'No phone',
      address: map['address'] ?? 'Not set',
    );
  }
}