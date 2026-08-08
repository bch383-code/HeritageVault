import 'package:flutter/material.dart';

class TimelineEvent {
  final String year;
  final String title;
  final String description;

  const TimelineEvent({
    required this.year,
    required this.title,
    required this.description,
  });
}

class HistoryTimeline extends StatelessWidget {
  final List<TimelineEvent> events;

  const HistoryTimeline({
    super.key,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(28),
      itemCount: events.length,
      separatorBuilder: (context, index) => const SizedBox(height: 18),
      itemBuilder: (context, index) {
        final event = events[index];

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 90,
              child: Text(
                event.year,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            Column(
              children: [
                Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                if (index != events.length - 1)
                  Container(
                    width: 2,
                    height: 90,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const SizedBox(height: 8),
                      Text(event.description),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}