package com.eureka.mindapp

import android.app.Application
import com.bairong.log.LogConfig
import com.bairong.log.LogInitializer

class EurekaApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        LogInitializer.init(
            this,
            LogConfig(
                enableLog = BuildConfig.DEBUG,
                enableFileLog = BuildConfig.DEBUG,
                defaultTag = "EurekaLog",
            ),
        )
    }
}
