import 'package:flutter/material.dart';

/// Landing-page marketing sections — Dart ports of
/// `manavizha/components/features-section.tsx` and
/// `manavizha/components/testimonials-section.tsx`. Each section reproduces
/// the web copy verbatim (titles, descriptions, feature names, rating
/// counts, testimonial quotes) and follows the same visual structure:
/// • Gradient eyebrow badge → bold heading → muted subtitle.
/// • Horizontally-scrollable card carousel (the web uses a CSS
///   `animate-scroll` keyframe with duplicated content for an infinite
///   loop; Flutter substitutes user-driven horizontal scrolling with snap,
///   which feels more native on mobile and avoids the extra render
///   complexity of a continuous auto-scroller).
///
/// Both sections are designed to be embedded inside the welcome
/// (`lib/welcome_screen.dart`) scroll view that mirrors the web home page
/// composition (`app/page.tsx`).

const Color _brandIndigo = Color(0xFF1F4068);
const Color _brandPurple = Color(0xFF4B0082);
const Color _brandPink = Color(0xFFFF1493);
const Color _brandAmber = Color(0xFFFFA500);

/// One marketing feature card (mirrors the web `features` array entries).
class FeatureItem {
  const FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradient,
  });
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradient;
}

const List<FeatureItem> _features = [
  FeatureItem(
    icon: Icons.shield_outlined,
    title: 'Verified Profiles',
    description:
        'All profiles are thoroughly verified to ensure authenticity and trust. '
        'We verify identity, education, and background.',
    gradient: [Color(0xFF3B82F6), Color(0xFF06B6D4)],
  ),
  FeatureItem(
    icon: Icons.search_rounded,
    title: 'Smart Matching',
    description:
        'Advanced AI-powered algorithm helps you find compatible matches based '
        'on your preferences, values, and lifestyle.',
    gradient: [_brandPurple, _brandIndigo],
  ),
  FeatureItem(
    icon: Icons.favorite_rounded,
    title: 'Privacy First',
    description:
        'Your data is secure with us. We prioritize your privacy and '
        'confidentiality with end-to-end encryption.',
    gradient: [_brandPink, _brandPurple],
  ),
  FeatureItem(
    icon: Icons.verified_rounded,
    title: 'Trusted Platform',
    description:
        'Join thousands of families who trust us for finding their perfect '
        'matches. 98% satisfaction rate.',
    gradient: [Color(0xFF10B981), Color(0xFF34D399)],
  ),
  FeatureItem(
    icon: Icons.chat_bubble_outline_rounded,
    title: 'Easy Communication',
    description:
        'Connect and communicate with potential matches through our secure, '
        'user-friendly messaging platform.',
    gradient: [_brandAmber, _brandPink],
  ),
  FeatureItem(
    icon: Icons.star_rounded,
    title: 'Premium Experience',
    description:
        'Enjoy a premium experience with personalized matchmaking services and '
        'dedicated support team.',
    gradient: [_brandAmber, _brandIndigo],
  ),
];

class FeaturesSection extends StatelessWidget {
  const FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _MarketingSection(
      eyebrow: 'Why Choose Us',
      heading: 'Everything You Need',
      subtitle:
          'Experience the best in matrimonial matchmaking with our '
          'comprehensive platform designed for modern families.',
      cardHeight: 260,
      cardWidth: 280,
      itemCount: _features.length,
      builder: (context, index) => _FeatureCard(item: _features[index]),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.item});
  final FeatureItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: item.gradient.first.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            // Top accent strip — same `bg-gradient-to-r` the web card uses.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: item.gradient,
                  ),
                ),
              ),
            ),
            // Decorative bottom-right corner glow.
            Positioned(
              right: -30,
              bottom: -30,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      item.gradient.first.withValues(alpha: 0.10),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: item.gradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: item.gradient.first.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(item.icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E1E1E),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        'Learn more',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: item.gradient.first,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: item.gradient.first,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TestimonialItem {
  const TestimonialItem({
    required this.name,
    required this.location,
    required this.text,
    required this.rating,
    required this.emoji,
  });
  final String name;
  final String location;
  final String text;
  final int rating;
  final String emoji;
}

const List<TestimonialItem> _testimonials = [
  TestimonialItem(
    name: 'Priya & Raj',
    location: 'Mumbai, India',
    text:
        'Manavizha helped us find each other. The platform is easy to use '
        "and the support team is amazing. We couldn't be happier!",
    rating: 5,
    emoji: '👫',
  ),
  TestimonialItem(
    name: 'Anjali & Vikram',
    location: 'Delhi, India',
    text:
        'The verification process gave us confidence, and the matching '
        'algorithm really understood our preferences. Highly recommended!',
    rating: 5,
    emoji: '💑',
  ),
  TestimonialItem(
    name: 'Meera & Arjun',
    location: 'Bangalore, India',
    text:
        'Privacy was our main concern, and Manavizha exceeded our '
        'expectations. We found our perfect match in just 3 months!',
    rating: 5,
    emoji: '💕',
  ),
];

class TestimonialsSection extends StatelessWidget {
  const TestimonialsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _MarketingSection(
      eyebrow: 'Success Stories',
      eyebrowIcon: Icons.auto_awesome_rounded,
      heading: 'Love Stories',
      subtitle:
          'Hear from couples who found their perfect match through Manavizha.',
      cardHeight: 300,
      cardWidth: 290,
      itemCount: _testimonials.length,
      builder: (context, index) => _TestimonialCard(item: _testimonials[index]),
    );
  }
}

class _TestimonialCard extends StatelessWidget {
  const _TestimonialCard({required this.item});
  final TestimonialItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: _brandPurple.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: Container(
                height: 4,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [_brandIndigo, _brandPurple, _brandPink],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.emoji,
                    style: const TextStyle(fontSize: 40, height: 1.0),
                  ),
                  const SizedBox(height: 8),
                  Icon(
                    Icons.format_quote_rounded,
                    size: 24,
                    color: _brandPurple.withValues(alpha: 0.35),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Text(
                      '"${item.text}"',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                        color: Colors.black.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < item.rating; i++)
                        const Padding(
                          padding: EdgeInsets.only(right: 2),
                          child: Icon(Icons.star_rounded,
                              size: 16, color: Color(0xFFFBBF24)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(height: 1, color: Colors.black.withValues(alpha: 0.08)),
                  const SizedBox(height: 10),
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E1E1E),
                    ),
                  ),
                  Text(
                    item.location,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared chrome for both marketing sections — eyebrow chip, heading,
/// subtitle, and a horizontally snapping `PageView`-backed carousel that
/// shows ~1.15 cards per page so users see a hint of the next card and
/// know it's swipeable. This is the Flutter analogue of the web carousel
/// (which uses an infinite CSS scroll animation instead).
class _MarketingSection extends StatelessWidget {
  const _MarketingSection({
    required this.eyebrow,
    this.eyebrowIcon,
    required this.heading,
    required this.subtitle,
    required this.cardHeight,
    required this.cardWidth,
    required this.itemCount,
    required this.builder,
  });

  final String eyebrow;
  final IconData? eyebrowIcon;
  final String heading;
  final String subtitle;
  final double cardHeight;
  final double cardWidth;
  final int itemCount;
  final IndexedWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                _brandIndigo.withValues(alpha: 0.18),
                _brandPurple.withValues(alpha: 0.18),
              ],
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrowIcon != null) ...[
                Icon(eyebrowIcon, size: 14, color: _brandPurple),
                const SizedBox(width: 6),
              ],
              Text(
                eyebrow,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                  color: _brandPurple,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [_brandIndigo, _brandPurple, _brandPink],
          ).createShader(rect),
          child: Text(
            heading,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.6,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: Colors.black.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            physics: const BouncingScrollPhysics(),
            itemCount: itemCount,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              return SizedBox(width: cardWidth, child: builder(context, index));
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swipe_rounded,
                size: 14, color: Colors.black.withValues(alpha: 0.4)),
            const SizedBox(width: 6),
            Text(
              'Swipe to explore',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
