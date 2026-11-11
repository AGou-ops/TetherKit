import Charts
import SwiftUI
import TetherKitIPC

/// 吞吐与计数器。
///
/// 图表刻意只画**速率**而不画累计量：累计曲线永远单调上升，看不出任何东西；
/// 而速率能一眼看出卡顿、抖动和被限速。累计量放在下面的指标格里，需要时能读到。
struct ThroughputCard: View {
    @Bindable var model: AppModel


    var body: some View {
        Card(title: L(.throughputSectionTitle), systemImage: "chart.line.uptrend.xyaxis", accessory: AnyView(liveBadge)) {
            VStack(alignment: .leading, spacing: Design.Spacing.medium) {
                rateRow
                chart
                Divider()
                counterRow
                if hasDrops {
                    dropHint
                }
            }
        }
    }

    @ViewBuilder
    private var liveBadge: some View {
        if model.status.runState == .running {
            StatusBadge(text: L(.throughputLive), color: .green)
        }
    }

    // 速率四格排成 2×2 而不是一行：这卡现在住在半栏里，一行四格会把
    // 「下行（设备 → 本机）」这类说明挤到截断。
    private var rateRow: some View {
        Grid(alignment: .leading,
             horizontalSpacing: Design.Spacing.medium,
             verticalSpacing: Design.Spacing.small) {
            GridRow {
                MetricTile(caption: L(.throughputDownstream),
                           value: Format.bitrate(model.throughput.receiveBitsPerSecond),
                           systemImage: "arrow.down",
                           tint: .blue)
                MetricTile(caption: L(.throughputUpstream),
                           value: Format.bitrate(model.throughput.transmitBitsPerSecond),
                           systemImage: "arrow.up",
                           tint: .purple)
            }
            GridRow {
                MetricTile(caption: L(.throughputDownstreamFPS),
                           value: "\(Format.packetsPerSecond(model.throughput.receivePacketsPerSecond)) pps",
                           systemImage: "square.stack.3d.up")
                MetricTile(caption: L(.throughputUpstreamFPS),
                           value: "\(Format.packetsPerSecond(model.throughput.transmitPacketsPerSecond)) pps",
                           systemImage: "square.stack.3d.up")
            }
        }
    }

    private var chart: some View {
        ThroughputChart(model: model)
    }

    private var counterRow: some View {
        HStack(spacing: Design.Spacing.medium) {
            MetricTile(caption: L(.totalDownstream), value: Format.bytes(model.sessionMetrics.rxBytes))
            MetricTile(caption: L(.totalUpstream), value: Format.bytes(model.sessionMetrics.txBytes))
            MetricTile(caption: L(.downstreamFrames), value: Format.count(model.sessionMetrics.rxFrames))
            MetricTile(caption: L(.upstreamFrames), value: Format.count(model.sessionMetrics.txFrames))
        }
    }

    private var hasDrops: Bool {
        model.sessionMetrics.rxDropped > 0 || model.sessionMetrics.txDropped > 0
            || model.sessionMetrics.linkKernelDrops > 0 || model.sessionMetrics.txBackpressure > 0
    }

    /// 丢包提示。
    ///
    /// 分开列四个数字而不是合成一个「丢包率」：它们指向完全不同的瓶颈 ——
    /// 队列满是下游写不过来，内核丢是我们读得不够快，背压是 USB 侧发不出去。
    /// 合并之后就分不清该调哪个参数了。
    private var dropHint: some View {
        HStack(spacing: Design.Spacing.medium) {
            MetricTile(caption: L(.downstreamDropped), value: Format.count(model.sessionMetrics.rxDropped), tint: .orange)
            MetricTile(caption: L(.upstreamDropped), value: Format.count(model.sessionMetrics.txDropped), tint: .orange)
            MetricTile(caption: L(.kernelDrops), value: Format.count(model.sessionMetrics.linkKernelDrops), tint: .orange)
            MetricTile(caption: L(.transmitBackpressure), value: Format.count(model.sessionMetrics.txBackpressure), tint: .orange)
        }
    }
}

private struct ThroughputChart: View {
    @Bindable var model: AppModel

    @ViewBuilder
    var body: some View {
        if !model.throughputHistory.isEmpty {
            let chartTimeLabel = L(.chartTime)
            let chartRateLabel = L(.chartRate)
            let chartDirectionLabel = L(.chartDirection)
            let downstreamLabel = L(.downstreamShort)
            let upstreamLabel = L(.upstreamShort)
            let areaGradient = LinearGradient(
                gradient: Gradient(colors: [.blue.opacity(0.35), .blue.opacity(0.02)]),
                startPoint: .top,
                endPoint: .bottom)
            Chart {
                ForEach(model.throughputHistory) { sample in
                    AreaMark(x: .value(chartTimeLabel, sample.timestamp),
                             y: .value(chartRateLabel, sample.receiveBitsPerSecond))
                        .foregroundStyle(areaGradient)
                        .interpolationMethod(.monotone)

                    LineMark(x: .value(chartTimeLabel, sample.timestamp),
                             y: .value(chartRateLabel, sample.receiveBitsPerSecond),
                             series: .value(chartDirectionLabel, downstreamLabel))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)

                    LineMark(x: .value(chartTimeLabel, sample.timestamp),
                             y: .value(chartRateLabel, sample.transmitBitsPerSecond),
                             series: .value(chartDirectionLabel, upstreamLabel))
                        .foregroundStyle(.purple)
                        .interpolationMethod(.monotone)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let bits = value.as(Double.self) {
                            Text(Format.bitrate(bits)).font(.caption2)
                        }
                    }
                }
            }
            // 横轴不画刻度：这是一条「最近 60 秒」的滚动曲线，具体时刻没有意义，
            // 画上去只会挤占本来就不高的绘图区。
            .chartXAxis(.hidden)
            .frame(height: 120)
        } else {
            RoundedRectangle(cornerRadius: Design.Radius.control)
                .fill(.quaternary.opacity(0.35))
                .frame(height: 120)
                .overlay(
                    Text(L(model.status.runState == .running ? .throughputCollecting : .throughputPlaceholder))
                        .font(.callout)
                        .foregroundStyle(.secondary))
        }
    }
}
