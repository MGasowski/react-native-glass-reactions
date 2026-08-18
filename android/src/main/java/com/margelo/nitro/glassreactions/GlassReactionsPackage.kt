package com.margelo.nitro.glassreactions

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager

class GlassReactionsPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider { HashMap() }
    }

    /**
     * The library exposes no React view managers. The picker is not a mounted
     * component: the native host presents a single pooled view into its own
     * overlay, and triggers are plain RN views the consumer already renders
     * (spec §4.3, §6.5).
     */
    override fun createViewManagers(
        reactContext: ReactApplicationContext
    ): List<ViewManager<*, *>> = emptyList()

    companion object {
        init {
            System.loadLibrary("glassreactions")
        }
    }
}
