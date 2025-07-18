import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:heavenly_homes/screens/pages/order_processing_page.dart';
import '../../constants/app_constants.dart';
import '../../model/cart_items.dart';
import '../../model/decoration_items.dart';

class ItemDetailPage extends StatefulWidget {
  final DecorationItem item;

  const ItemDetailPage({super.key, required this.item});

  @override
  State<ItemDetailPage> createState() => _ItemDetailPageState();
}

class _ItemDetailPageState extends State<ItemDetailPage> {
  String _selectedImageUrl = '';
  bool _isAddingToCart = false;
  bool _isBuyingNow = false;

  @override
  void initState() {
    super.initState();
    _selectedImageUrl = widget.item.imageUrl;
  }

  Future<int> _checkAvailableQuantity() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('decoration_items')
          .doc(widget.item.id)
          .get();
      return doc.exists ? (doc.data()?['available_qty'] as num?)?.toInt() ?? 0 : 0;
    } catch (e) {
      //print("Error checking quantity: $e");
      return 0;
    }
  }

  void _showOutOfStockDialog() {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Out of Stock'),
        content: const Text('Sorry, this item is currently out of stock.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showQuantityExceededDialog(int availableQty) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Limit Reached'),
        content: Text('You already have the maximum available quantity ($availableQty) in your cart.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _addToCart() async {
    if (_isAddingToCart || _isBuyingNow) return;
    setState(() => _isAddingToCart = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      setState(() => _isAddingToCart = false);
      return;
    }
    final availableQty = await _checkAvailableQuantity();
    if (availableQty <= 0) {
      _showOutOfStockDialog();
      setState(() => _isAddingToCart = false);
      return;
    }

    try {
      final cartSnapshot = await FirebaseFirestore.instance
          .collection('cart')
          .where('userId', isEqualTo: user.uid)
          .where('decorationItemId', isEqualTo: widget.item.id)
          .limit(1)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      if (cartSnapshot.docs.isNotEmpty) {
        final cartDoc = cartSnapshot.docs.first;
        final currentQty = (cartDoc.data()['quantity'] as num?)?.toInt() ?? 0;
        final newQty = currentQty + 1;
        if (newQty > availableQty) {
          _showQuantityExceededDialog(availableQty);
          setState(() => _isAddingToCart = false);
          return;
        }
        batch.update(cartDoc.reference, {'quantity': newQty});
      } else {
        final cartItem = CartItem(
          id: '',
          userId: user.uid,
          decorationItemId: widget.item.id,
          name: widget.item.name,
          imageUrl: widget.item.imageUrl,
          price: widget.item.price,
          discountedPrice: widget.item.isDiscounted ? widget.item.discountedPrice : null,
          quantity: 1,
        );
        final cartDocRef = FirebaseFirestore.instance.collection('cart').doc();
        batch.set(cartDocRef, cartItem.toFirestore());
      }
      await batch.commit();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.item.name} added to cart!'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      //print("Error adding to cart: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding item: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAddingToCart = false);
      }
    }
  }

  Future<void> _buyNow() async {
    if (_isAddingToCart || _isBuyingNow) return;
    setState(() => _isBuyingNow = true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) Navigator.pushReplacementNamed(context, '/login');
      setState(() => _isBuyingNow = false);
      return;
    }

    final availableQty = await _checkAvailableQuantity();
    if (availableQty <= 0) {
      _showOutOfStockDialog();
      setState(() => _isBuyingNow = false);
      return;
    }

    final itemToProcess = CartItem(
      id: 'details_${widget.item.id}',
      userId: user.uid,
      decorationItemId: widget.item.id,
      name: widget.item.name,
      imageUrl: _selectedImageUrl,
      price: widget.item.price,
      discountedPrice: widget.item.isDiscounted ? widget.item.discountedPrice : null,
      quantity: 1,
    );

    const deliveryCharges = 350.0;
    final subtotal = itemToProcess.discountedPrice ?? itemToProcess.price;
    final totalAmount = subtotal + deliveryCharges;

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OrderProcessingPage(
            cartItems: [itemToProcess],
            orderId: '',
            userId: user.uid,
            deliveryCharges: deliveryCharges,
            subtotal: subtotal,
            totalAmount: totalAmount,
            viewMode: 'Details',
          ),
        ),
      );
    }

    if (mounted) {
      setState(() => _isBuyingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 300,
              width: double.infinity,
              child: Stack(
                children: [
                  _selectedImageUrl.startsWith('http')
                      ? Image.network(
                    _selectedImageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 300,
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                  )
                      : Image.asset(
                    _selectedImageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 300,
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 50),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: IconButton(
                        icon: const Icon(Icons.favorite_border),
                        color: Colors.white,
                        onPressed: () {},
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.item.subImages.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  itemCount: widget.item.subImages.length,
                  itemBuilder: (context, index) {
                    final subImageUrl = widget.item.subImages[index];
                    return GestureDetector(
                      onTap: () => setState(() => _selectedImageUrl = subImageUrl),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: subImageUrl.startsWith('http')
                              ? Image.network(
                            subImageUrl,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 40),
                          )
                              : Image.asset(
                            subImageUrl,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 40),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.name,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Row(
                        children: List.generate(5, (index) {
                          return Icon(
                            index < widget.item.rating.floor()
                                ? Icons.star
                                : (index < widget.item.rating ? Icons.star_half : Icons.star_border),
                            color: Colors.amber,
                            size: 20,
                          );
                        }),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.item.reviewCount} reviews',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.item.isDiscounted && widget.item.discountedPrice != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rs ${widget.item.price.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          'Rs ${widget.item.discountedPrice!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Rs ${widget.item.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.item.description,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 160),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppConstants.panelBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(50)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 25.0, vertical: 30.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            ElevatedButton(
              onPressed: _isAddingToCart || _isBuyingNow ? null : _addToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.buttonBackground,
                foregroundColor: AppConstants.buttonTextColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                minimumSize: const Size(161, 44.08),
                padding: EdgeInsets.zero,
                elevation: 2,
                disabledBackgroundColor: AppConstants.buttonBackground.withValues(alpha: 0.5),
              ),
              child: _isAddingToCart
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppConstants.buttonTextColor),
              )
                  : const Text(
                'Add to Cart',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontWeight: FontWeight.w700,
                  fontSize: 18.5,
                  height: 1.0,
                  letterSpacing: -0.02 * 18.5,
                  color: AppConstants.buttonTextColor,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _isAddingToCart || _isBuyingNow ? null : _buyNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppConstants.buyNowButtonBackground,
                foregroundColor: AppConstants.buyNowButtonTextColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                minimumSize: const Size(161, 46),
                padding: EdgeInsets.zero,
                elevation: 2,
                disabledBackgroundColor: AppConstants.buyNowButtonBackground.withValues(alpha: 0.5),
              ),
              child: _isBuyingNow
                  ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppConstants.buyNowButtonTextColor),
              )
                  : const Text(
                'Buy Now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lato',
                  fontWeight: FontWeight.w700,
                  fontSize: 18.5,
                  height: 1.0,
                  letterSpacing: -0.02 * 18.5,
                  color: AppConstants.buyNowButtonTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}