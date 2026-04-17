import org.gradle.api.tasks.Sync

plugins {
    id("com.android.asset-pack")
}

val syncPackAssets by tasks.registering(Sync::class) {
    from("../../../assets/instruments")
    into(layout.projectDirectory.dir("src/main/assets/assets/instruments"))
}

tasks.configureEach {
    if (name != syncPackAssets.name) {
        dependsOn(syncPackAssets)
    }
}

assetPack {
    packName.set("instruments")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}
