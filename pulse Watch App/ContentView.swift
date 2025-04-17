//
//  ContentView.swift
//  pulse Watch App
//
//  Created by lixumin on 2025/4/16.
//

import SwiftUI
import HealthKit
import WatchKit

struct ContentView: View {
    // 创建状态变量来存储心率数据
    @State private var heartRate: Double = 0
    @State private var isAuthorized: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false
    @State private var isPressed: Bool = false // 添加按压状态变量
    
    // 创建HealthKit存储实例
    private var healthStore = HKHealthStore()
    private let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    
    // 添加震动计时器
    @State private var vibrationTimer: Timer? = nil
    @State private var heartbeatInterval: Double = 0
    
    var body: some View {
        ZStack {
            // 背景
            Color.black.edgesIgnoringSafeArea(.all)
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .red))
                    .scaleEffect(1.5)
            } else if let error = errorMessage {
                // 错误视图
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30))
                        .foregroundColor(.yellow)
                    
                    Text("错误")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        errorMessage = nil
                        requestAuthorization()
                    }) {
                        Text("重试")
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding()
            } else if isAuthorized {
                // 心率显示视图
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                        
                        Text("心率")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    
                    Text("\(Int(heartRate))")
                        .font(.system(size: 50, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("BPM")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    // 心率动画
                    HeartRateAnimation(heartRate: heartRate)
                    
                    // 添加提示文本
                    Text("按住屏幕感受心跳")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .padding(.top, 10)
                }
                .padding()
                // 添加长按手势
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPressed {
                                isPressed = true
                                startHeartbeatVibration()
                            }
                        }
                        .onEnded { _ in
                            isPressed = false
                            stopHeartbeatVibration()
                        }
                )
            } else {
                // 未授权视图
                VStack(spacing: 12) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 30))
                        .foregroundColor(.gray)
                    
                    Text("需要健康数据权限")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Button(action: {
                        requestAuthorization()
                    }) {
                        Text("授权访问")
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.red)
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            isLoading = true
            checkHealthKitAuthorization()
        }
        .onDisappear {
            stopHeartbeatVibration()
        }
    }
    
    // 检查HealthKit授权状态
    private func checkHealthKitAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            isLoading = false
            errorMessage = "此设备不支持HealthKit"
            return
        }
        
        // Fix: Create an empty set instead of nil for toShare parameter
        let typesToShare: Set<HKSampleType> = []
        
        healthStore.getRequestStatusForAuthorization(toShare: typesToShare, read: [heartRateType]) { status, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    errorMessage = "检查授权状态失败: \(error.localizedDescription)"
                    return
                }
                
                switch status {
                case .unnecessary:
                    // 已授权
                    isAuthorized = true
                    startHeartRateQuery()
                default:
                    // 需要请求授权
                    requestAuthorization()
                }
            }
        }
    }
    
    // 请求HealthKit授权
    private func requestAuthorization() {
        isLoading = true
        
        guard HKHealthStore.isHealthDataAvailable() else {
            isLoading = false
            errorMessage = "此设备不支持HealthKit"
            return
        }
        
        let typesToRead: Set<HKObjectType> = [heartRateType]
        
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if success {
                    isAuthorized = true
                    startHeartRateQuery()
                } else if let error = error {
                    errorMessage = "授权请求失败: \(error.localizedDescription)"
                    print("授权请求失败: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // 开始查询心率数据
    private func startHeartRateQuery() {
        // 创建查询的描述符
        let datePredicate = HKQuery.predicateForSamples(withStart: Date.distantPast, end: Date(), options: .strictEndDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        // 创建查询
        let query = HKSampleQuery(sampleType: heartRateType, predicate: datePredicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, error in
            if let error = error {
                DispatchQueue.main.async {
                    errorMessage = "获取心率数据失败: \(error.localizedDescription)"
                }
                return
            }
            
            guard let samples = results as? [HKQuantitySample], let sample = samples.first else {
                print("没有找到心率数据")
                // 即使没有找到数据，也设置观察者以捕获未来的心率
                self.startHeartRateObserver()
                return
            }
            
            // 更新UI
            DispatchQueue.main.async {
                self.heartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
            
            // 设置观察查询以持续监控心率变化
            self.startHeartRateObserver()
        }
        
        // 执行查询
        healthStore.execute(query)
    }
    
    // 设置心率观察者以实时更新数据
    private func startHeartRateObserver() {
        let query = HKObserverQuery(sampleType: heartRateType, predicate: nil) { query, completionHandler, error in
            if let error = error {
                print("观察者查询错误: \(error.localizedDescription)")
                completionHandler()
                return
            }
            
            self.fetchLatestHeartRate()
            completionHandler()
        }
        
        healthStore.execute(query)
        
        // 启用后台传递
        healthStore.enableBackgroundDelivery(for: heartRateType, frequency: .immediate) { success, error in
            if let error = error {
                print("启用后台传递失败: \(error.localizedDescription)")
            }
        }
    }
    
    // 获取最新的心率数据
    private func fetchLatestHeartRate() {
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, error in
            guard let samples = results as? [HKQuantitySample], let sample = samples.first else {
                return
            }
            
            DispatchQueue.main.async {
                self.heartRate = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            }
        }
        
        healthStore.execute(query)
    }
    // 添加心跳震动功能
    private func startHeartbeatVibration() {
        // 停止现有计时器
        vibrationTimer?.invalidate()
        
        // 创建新计时器，使用较短的间隔频繁检查心率
        vibrationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [self] timer in
            // 计算当前心率对应的心跳间隔（秒）
            let currentHeartbeatInterval = 60.0 / max(self.heartRate, 60)
            print(currentHeartbeatInterval)
            // 累加计时器运行时间
            self.heartbeatInterval += 0.1
            
            // 当累积时间达到或超过心跳间隔时触发震动
            if self.heartbeatInterval >= currentHeartbeatInterval {
                // 触发震动
                WKInterfaceDevice.current().play(.click)
                // 重置累积时间，但保留可能的余数以保持精确的节奏
                self.heartbeatInterval = self.heartbeatInterval.truncatingRemainder(dividingBy: currentHeartbeatInterval)
            }
        }
        
        // 重置累积时间
        self.heartbeatInterval = 0
        
        // 立即触发第一次震动
        WKInterfaceDevice.current().play(.click)
    }
    
    private func stopHeartbeatVibration() {
        vibrationTimer?.invalidate()
        vibrationTimer = nil
        heartbeatInterval = 0 // 重置累积时间
    }
}

// 心率动画组件
struct HeartRateAnimation: View {
    let heartRate: Double
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 40))
            .foregroundColor(.red)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 60/max(heartRate, 60)).repeatForever(autoreverses: true)) {
                    scale = 1.3
                }
            }
    }
}

#Preview {
    ContentView()
}
