import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
  import ActivityKit

  /// Kafel rezerwacji na ekranie blokady: nazwa lokalu po lewej, godzina po prawej,
  /// a pod spodem przycisk „Nawiguj”.
  @available(iOS 16.2, *)
  struct TableActivityWidget: Widget {
    var body: some WidgetConfiguration {
      ActivityConfiguration(for: TableReservationAttributes.self) { context in
        LockScreenView(context: context)
          .activityBackgroundTint(Color.black.opacity(0.55))
          .activitySystemActionForegroundColor(Color.white)
      } dynamicIsland: { context in
        DynamicIsland {
          DynamicIslandExpandedRegion(.leading) {
            Text(context.attributes.restaurantName)
              .font(.headline)
              .lineLimit(1)
          }
          DynamicIslandExpandedRegion(.trailing) {
            Text(context.state.startsAt, style: .time)
              .font(.headline.monospacedDigit())
          }
          DynamicIslandExpandedRegion(.bottom) {
            NavigateButton(address: context.attributes.address)
          }
        } compactLeading: {
          Image(systemName: "fork.knife")
        } compactTrailing: {
          Text(context.state.startsAt, style: .time)
            .font(.caption.monospacedDigit())
        } minimal: {
          Image(systemName: "fork.knife")
        }
      }
    }
  }

  @available(iOS 16.2, *)
  private struct LockScreenView: View {
    let context: ActivityViewContext<TableReservationAttributes>

    var body: some View {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 2) {
            Text(context.attributes.restaurantName)
              .font(.headline)
              .lineLimit(1)
            if !context.state.details.isEmpty {
              Text(context.state.details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
          Spacer(minLength: 12)
          Text(context.state.startsAt, style: .time)
            .font(.title2.monospacedDigit().weight(.semibold))
        }
        NavigateButton(address: context.attributes.address)
      }
      .padding(16)
    }
  }

  /// Otwiera Mapy Apple z trasą do lokalu. Link działa wprost z ekranu blokady.
  @available(iOS 16.2, *)
  private struct NavigateButton: View {
    let address: String

    private var url: URL {
      let target =
        address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
      return URL(string: "https://maps.apple.com/?daddr=\(target)")!
    }

    var body: some View {
      Link(destination: url) {
        HStack(spacing: 6) {
          Image(systemName: "location.fill")
          Text("Nawiguj")
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.16), in: Capsule())
      }
      .tint(.white)
    }
  }

  @main
  struct TableActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
      TableActivityWidget()
    }
  }
#endif
