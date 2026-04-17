import org.gradle.api.tasks.Sync

plugins {
    id("com.android.asset-pack")
}

val syncPackAssets by tasks.registering(Sync::class) {
    from("../../../assets/sample_packs")
    into(layout.projectDirectory.dir("src/main/assets/assets/sample_packs"))
}

tasks.configureEach {
    if (name != syncPackAssets.name) {
        dependsOn(syncPackAssets)
    }
}

assetPack {
    packName.set("sample_packs")
    dynamicDelivery {
        deliveryType.set("install-time")
    }
}
