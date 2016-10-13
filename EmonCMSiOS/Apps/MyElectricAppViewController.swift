//
//  MyElectricAppViewController.swift
//  EmonCMSiOS
//
//  Created by Matt Galloway on 14/09/2016.
//  Copyright © 2016 Matt Galloway. All rights reserved.
//

import UIKit

import RxSwift
import RxCocoa
import Charts

class MyElectricAppViewController: UIViewController {

  var viewModel: MyElectricAppViewModel!

  @IBOutlet private var mainView: UIView!
  @IBOutlet private var powerLabel: UILabel!
  @IBOutlet private var usageTodayLabel: UILabel!
  @IBOutlet fileprivate var lineChart: LineChartView!
  @IBOutlet fileprivate var barChart: BarChartView!

  @IBOutlet private var configureView: UIView!

  private let disposeBag = DisposeBag()

  override func viewDidLoad() {
    super.viewDidLoad()

    self.setupCharts()
    self.setupBindings()
    self.setupNavigation()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    self.viewModel.active.value = true
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(true)
    self.viewModel.active.value = false
  }

  private func setupBindings() {
    self.viewModel.title
      .drive(self.rx.title)
      .addDisposableTo(self.disposeBag)

    self.viewModel.data
      .map { $0.powerNow }
      .map { $0.prettyFormat() + "W" }
      .drive(self.powerLabel.rx.text)
      .addDisposableTo(self.disposeBag)

    self.viewModel.data
      .map { $0.usageToday }
      .map { $0.prettyFormat() + "kWh" }
      .drive(self.usageTodayLabel.rx.text)
      .addDisposableTo(self.disposeBag)

    self.viewModel.data
      .map { $0.lineChartData }
      .drive(onNext: { [weak self] dataPoints in
        guard let strongSelf = self else { return }
        strongSelf.updateLineChartData(dataPoints)
        })
      .addDisposableTo(self.disposeBag)

    self.viewModel.data
      .map { $0.barChartData }
      .drive(onNext: { [weak self] dataPoints in
        guard let strongSelf = self else { return }
        strongSelf.updateBarChartData(dataPoints)
        })
      .addDisposableTo(self.disposeBag)

    self.viewModel.isReady
      .map { !$0 }
      .drive(self.mainView.rx.hidden)
      .addDisposableTo(self.disposeBag)

    self.viewModel.isReady
      .drive(self.configureView.rx.hidden)
      .addDisposableTo(self.disposeBag)
  }

  private func setupNavigation() {
    let rightBarButtonItem = UIBarButtonItem(title: "Configure", style: .plain, target: nil, action: nil)
    rightBarButtonItem.rx.tap
      .flatMap { [weak self] _ -> Driver<String?> in
        guard let strongSelf = self else { return Driver.empty() }

        let configViewController = AppConfigViewController()
        configViewController.viewModel = strongSelf.viewModel.configViewModel()
        let navController = UINavigationController(rootViewController: configViewController)
        strongSelf.present(navController, animated: true, completion: nil)

        return configViewController.finished
      }
      .subscribe(onNext: { [weak self] _ in
        guard let strongSelf = self else { return }
        strongSelf.dismiss(animated: true, completion: nil)
        })
      .addDisposableTo(self.disposeBag)
    self.navigationItem.rightBarButtonItem = rightBarButtonItem
  }

}

extension MyElectricAppViewController {

  fileprivate func setupCharts() {
    self.setupLineChart()
    self.setupBarChart()
  }

  fileprivate func setupLineChart() {
    guard let lineChart = self.lineChart else {
      return
    }

    lineChart.drawGridBackgroundEnabled = false
    lineChart.legend.enabled = false
    lineChart.rightAxis.enabled = false
    lineChart.chartDescription = nil
    lineChart.noDataText = ""

    let xAxis = lineChart.xAxis
    xAxis.drawAxisLineEnabled = false
    xAxis.drawGridLinesEnabled = false
    xAxis.drawLabelsEnabled = true
    xAxis.labelPosition = .bottom
    xAxis.labelTextColor = .black
    xAxis.valueFormatter = ChartDateValueFormatter(.auto)
    xAxis.granularity = 3600

    let yAxis = lineChart.leftAxis
    yAxis.labelPosition = .insideChart
    yAxis.drawTopYLabelEntryEnabled = false
    yAxis.drawGridLinesEnabled = false
    yAxis.drawAxisLineEnabled = false
    yAxis.labelTextColor = .black

    let data = LineChartData()
    lineChart.data = data
  }

  fileprivate func setupBarChart() {
    guard let barChart = self.barChart else {
      return
    }

    barChart.drawGridBackgroundEnabled = false
    barChart.legend.enabled = false
    barChart.leftAxis.enabled = false
    barChart.rightAxis.enabled = false
    barChart.chartDescription = nil
    barChart.noDataText = ""
    barChart.isUserInteractionEnabled = false
    barChart.extraBottomOffset = 2
    barChart.drawValueAboveBarEnabled = true

    let xAxis = barChart.xAxis
    xAxis.labelPosition = .bottomInside
    xAxis.labelTextColor = .white
    xAxis.valueFormatter = DayRelativeToTodayValueFormatter()
    xAxis.drawGridLinesEnabled = false
    xAxis.drawAxisLineEnabled = false
    xAxis.drawLabelsEnabled = true
    xAxis.granularity = 1
    xAxis.labelCount = 14

    let data = BarChartData()
    barChart.data = data
  }

  fileprivate func updateLineChartData(_ dataPoints: [DataPoint]) {
    guard let data = self.lineChart.data else { return }

    var entries: [ChartDataEntry] = []
    for point in dataPoints {
      let x = point.time.timeIntervalSince1970
      let y = point.value

      let yDataEntry = ChartDataEntry(x: x, y: y)
      entries.append(yDataEntry)
    }

    let dataSet: IChartDataSet
    if let ds = data.getDataSetByIndex(0) {
      ds.clear()
      for entry in entries {
        _ = ds.addEntry(entry)
      }
      dataSet = ds
    } else {
      let ds = LineChartDataSet(values: entries, label: nil)
      ds.setColor(EmonCMSColors.Chart.Blue)
      ds.fillColor = EmonCMSColors.Chart.Blue
      ds.valueTextColor = .black
      ds.drawFilledEnabled = true
      ds.drawCirclesEnabled = false
      ds.drawValuesEnabled = false
      ds.highlightEnabled = false
      data.addDataSet(ds)
      dataSet = ds
    }

    dataSet.notifyDataSetChanged()
    data.notifyDataChanged()
    self.lineChart.notifyDataSetChanged()
  }

  fileprivate func updateBarChartData(_ dataPoints: [DataPoint]) {
    guard let data = self.barChart.data else { return }

    var entries: [ChartDataEntry] = []
    for point in dataPoints {
      // 'x' here means the offset in days from 'today'
      let x = floor(point.time.timeIntervalSinceNow / 86400)
      let y = point.value

      let yDataEntry = BarChartDataEntry(x: x, y: y)
      entries.append(yDataEntry)
    }

    let dataSet: IChartDataSet
    if let ds = data.getDataSetByIndex(0) {
      ds.clear()
      for entry in entries {
        _ = ds.addEntry(entry)
      }
      dataSet = ds
    } else {
      let ds = BarChartDataSet(values: entries, label: "kWh")
      ds.setColor(EmonCMSColors.Chart.Blue)
      ds.valueTextColor = .black
      data.addDataSet(ds)
      dataSet = ds
    }

    dataSet.notifyDataSetChanged()
    data.notifyDataChanged()
    self.barChart.notifyDataSetChanged()
  }

}
