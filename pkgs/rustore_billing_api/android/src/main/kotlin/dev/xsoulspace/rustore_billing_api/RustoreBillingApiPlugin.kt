package dev.xsoulspace.rustore_billing_api

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import ru.rustore.sdk.billingclient.RuStoreBillingClient
import ru.rustore.sdk.billingclient.RuStoreBillingClientFactory
import ru.rustore.sdk.billingclient.model.product.Product
import ru.rustore.sdk.billingclient.model.product.ProductStatus
import ru.rustore.sdk.billingclient.model.product.ProductType
import ru.rustore.sdk.billingclient.model.product.SubscriptionPeriod
import ru.rustore.sdk.billingclient.model.purchase.PaymentResult
import ru.rustore.sdk.billingclient.model.purchase.Purchase
import ru.rustore.sdk.billingclient.model.purchase.PurchaseAvailabilityResult
import ru.rustore.sdk.billingclient.model.purchase.PurchaseState
import ru.rustore.sdk.billingclient.presentation.BillingClientTheme
import ru.rustore.sdk.billingclient.provider.BillingClientThemeProvider
import ru.rustore.sdk.billingclient.utils.pub.checkPurchasesAvailability
import ru.rustore.sdk.core.exception.RuStoreException
import ru.rustore.sdk.core.exception.RuStoreNotInstalledException
import ru.rustore.sdk.core.exception.RuStoreOutdatedException
import ru.rustore.sdk.core.exception.RuStoreUserUnauthorizedException
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

class RustoreBillingApiPlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.NewIntentListener,
    RustoreBillingApi {
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var billingClient: RuStoreBillingClient? = null
    private var callbackApi: RustoreBillingCallbackApi? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main.immediate + SupervisorJob())

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        RustoreBillingApi.setUp(binding.binaryMessenger, this)
        callbackApi = RustoreBillingCallbackApi(binding.binaryMessenger)
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        RustoreBillingApi.setUp(binding.binaryMessenger, null)
        callbackApi = null
        billingClient = null
        billingClientConfig = null
        context = null
        coroutineScope.cancel()
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        billingClient?.onNewIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        activity = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        billingClient?.onNewIntent(intent)
        return false
    }

    override fun initialize(config: RustoreBillingConfig, callback: (Result<Unit>) -> Unit) {
        try {
            val appContext = activity ?: context
                ?: throw IllegalStateException("Plugin is not attached to context")
            billingClient = RuStoreBillingClientFactory.create(
                context = appContext,
                consoleApplicationId = config.consoleApplicationId,
                deeplinkScheme = config.deeplinkScheme,
                debugLogs = config.debugLogs,
                themeProvider = StaticBillingThemeProvider(
                    mapThemeToSdk(config.defaultTheme),
                ),
            )
            billingClientConfig = config
            activity?.intent?.let { billingClient?.onNewIntent(it) }
            callback(Result.success(Unit))
        } catch (e: Throwable) {
            callback(Result.failure(e))
        }
    }

    override fun getPurchaseAvailability(
        callback: (Result<RustorePurchaseAvailabilityResult>) -> Unit,
    ) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                val availability = withContext(Dispatchers.IO) {
                    client.purchases.checkPurchasesAvailability().await()
                }
                callback(Result.success(mapPurchaseAvailabilityResult(availability)))
            } catch (e: Throwable) {
                callback(
                    Result.success(
                        RustorePurchaseAvailabilityResult(
                            status = RustorePurchaseAvailabilityStatus.UNAVAILABLE,
                            cause = mapException(e),
                        ),
                    ),
                )
            }
        }
    }

    override fun getUserAuthorizationStatus(callback: (Result<Boolean>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                val authStatus = withContext(Dispatchers.IO) {
                    client.userInfo.getAuthorizationStatus().await()
                }
                callback(Result.success(authStatus.authorized))
            } catch (e: Throwable) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getProducts(
        productIds: List<String>,
        callback: (Result<List<RustoreProduct>>) -> Unit,
    ) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                val products = withContext(Dispatchers.IO) {
                    client.products.getProducts(productIds).await()
                }
                callback(Result.success(products.map(::mapProduct)))
            } catch (e: Throwable) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getPurchases(
        filter: RustorePurchaseFilter?,
        callback: (Result<List<RustorePurchase>>) -> Unit,
    ) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                val purchases = withContext(Dispatchers.IO) {
                    client.purchases.getPurchases().await()
                }
                val mapped = purchases.map(::mapPurchase).filter { purchase ->
                    matchesFilter(purchase, filter)
                }
                callback(Result.success(mapped))
            } catch (e: Throwable) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getPurchase(
        purchaseId: String,
        callback: (Result<RustorePurchase?>) -> Unit,
    ) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                val purchase = withContext(Dispatchers.IO) {
                    client.purchases.getPurchaseInfo(purchaseId).await()
                }
                callback(Result.success(mapPurchase(purchase)))
            } catch (e: Throwable) {
                callback(Result.failure(e))
            }
        }
    }

    override fun purchase(
        params: RustoreProductPurchaseParams,
        preferredPurchaseType: RustorePreferredPurchaseType,
        sdkTheme: RustoreBillingTheme,
        callback: (Result<RustoreProductPurchaseResult>) -> Unit,
    ) {
        executePurchase(
            params = params,
            purchaseType = preferredPurchaseType.toPurchaseType(),
            sdkTheme = sdkTheme,
            callback = callback,
        )
    }

    override fun purchaseTwoStep(
        params: RustoreProductPurchaseParams,
        sdkTheme: RustoreBillingTheme,
        callback: (Result<RustoreProductPurchaseResult>) -> Unit,
    ) {
        executePurchase(
            params = params,
            purchaseType = RustorePurchaseType.TWO_STEP,
            sdkTheme = sdkTheme,
            callback = callback,
        )
    }

    private fun executePurchase(
        params: RustoreProductPurchaseParams,
        purchaseType: RustorePurchaseType,
        sdkTheme: RustoreBillingTheme,
        callback: (Result<RustoreProductPurchaseResult>) -> Unit,
    ) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                withContext(Dispatchers.Main) {
                    // SDK reads the theme provider at UI launch time.
                    val config = billingClientConfig
                        ?: throw IllegalStateException(
                            "Billing client config is missing. Call initialize() first.",
                        )
                    billingClient = RuStoreBillingClientFactory.create(
                        context = activity ?: context
                            ?: throw IllegalStateException("Plugin is not attached to context"),
                        consoleApplicationId = config.consoleApplicationId,
                        deeplinkScheme = config.deeplinkScheme,
                        debugLogs = config.debugLogs,
                        themeProvider = StaticBillingThemeProvider(mapThemeToSdk(sdkTheme)),
                    )
                }
                val result = withContext(Dispatchers.IO) {
                    billingClient!!.purchases.purchaseProduct(
                        productId = params.productId,
                        developerPayload = params.developerPayload,
                        quantity = params.quantity?.toInt(),
                    ).await()
                }
                val mapped = mapPaymentResult(result, purchaseType)
                callback(Result.success(mapped))
                callbackApi?.onPurchaseResult(mapped) { }
            } catch (e: Throwable) {
                val mappedError = mapPurchaseThrowable(e)
                callback(
                    Result.success(
                        RustoreProductPurchaseResult(
                            resultType = RustoreProductPurchaseResultType.FAILURE,
                            error = mappedError,
                        ),
                    ),
                )
                callbackApi?.onPurchaseError(mappedError) { }
            }
        }
    }

    private var billingClientConfig: RustoreBillingConfig? = null

    override fun confirmTwoStepPurchase(
        purchaseId: String,
        developerPayload: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    if (developerPayload == null) {
                        client.purchases.confirmPurchase(purchaseId).await()
                    } else {
                        client.purchases.confirmPurchase(purchaseId, developerPayload).await()
                    }
                }
                callback(Result.success(Unit))
            } catch (e: Throwable) {
                callback(Result.failure(e))
            }
        }
    }

    override fun cancelTwoStepPurchase(
        purchaseId: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client is not initialized")))
            return
        }
        coroutineScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    client.purchases.deletePurchase(purchaseId).await()
                }
                callback(Result.success(Unit))
            } catch (e: Throwable) {
                callback(Result.failure(e))
            }
        }
    }

    private fun mapPurchaseAvailabilityResult(
        result: PurchaseAvailabilityResult,
    ): RustorePurchaseAvailabilityResult {
        return when (result) {
            is PurchaseAvailabilityResult.Available -> RustorePurchaseAvailabilityResult(
                status = RustorePurchaseAvailabilityStatus.AVAILABLE,
            )
            is PurchaseAvailabilityResult.Unavailable -> RustorePurchaseAvailabilityResult(
                status = RustorePurchaseAvailabilityStatus.UNAVAILABLE,
                cause = mapException(result.cause),
            )
            is PurchaseAvailabilityResult.Unknown -> RustorePurchaseAvailabilityResult(
                status = RustorePurchaseAvailabilityStatus.UNKNOWN,
            )
            else -> RustorePurchaseAvailabilityResult(
                status = RustorePurchaseAvailabilityStatus.UNKNOWN,
            )
        }
    }

    private fun mapProduct(product: Product): RustoreProduct {
        val subscriptionPeriods = mutableListOf<RustoreProductSubscriptionPeriod>()
        product.subscription?.subscriptionPeriod?.let { period ->
            subscriptionPeriods.add(
                RustoreProductSubscriptionPeriod(
                    type = RustoreSubscriptionPeriodType.MAIN,
                    durationIso = period.toIsoDuration(),
                    price = product.price?.toLong(),
                    priceLabel = product.priceLabel,
                    currency = product.currency,
                ),
            )
        }
        product.subscription?.freeTrialPeriod?.let { period ->
            subscriptionPeriods.add(
                RustoreProductSubscriptionPeriod(
                    type = RustoreSubscriptionPeriodType.TRIAL,
                    durationIso = period.toIsoDuration(),
                ),
            )
        }
        product.subscription?.gracePeriod?.let { period ->
            subscriptionPeriods.add(
                RustoreProductSubscriptionPeriod(
                    type = RustoreSubscriptionPeriodType.GRACE,
                    durationIso = period.toIsoDuration(),
                ),
            )
        }
        product.subscription?.introductoryPricePeriod?.let { period ->
            subscriptionPeriods.add(
                RustoreProductSubscriptionPeriod(
                    type = RustoreSubscriptionPeriodType.INTRO,
                    durationIso = period.toIsoDuration(),
                    priceLabel = product.subscription?.introductoryPrice,
                    currency = product.currency,
                ),
            )
        }

        val subscriptionInfo = if (subscriptionPeriods.isEmpty()) {
            null
        } else {
            RustoreProductSubscriptionInfo(periods = subscriptionPeriods)
        }

        return RustoreProduct(
            productId = product.productId,
            productType = mapProductType(product.productType),
            productStatus = mapProductStatus(product.productStatus),
            title = product.title,
            description = product.description,
            price = product.price?.toLong(),
            priceLabel = product.priceLabel,
            currency = product.currency,
            language = product.language,
            subscriptionInfo = subscriptionInfo,
        )
    }

    private fun mapPurchase(purchase: Purchase): RustorePurchase {
        val purchaseStatus = mapPurchaseStatus(purchase.purchaseState)
        return RustorePurchase(
            purchaseId = purchase.purchaseId ?: "",
            purchaseType = inferPurchaseType(purchase.purchaseState),
            productType = mapProductType(purchase.productType),
            purchaseStatus = purchaseStatus,
            productId = purchase.productId,
            invoiceId = purchase.invoiceId,
            orderId = purchase.orderId,
            amountLabel = purchase.amountLabel,
            amount = purchase.amount?.toLong(),
            currency = purchase.currency,
            quantity = purchase.quantity?.toLong(),
            purchaseTime = formatDateToIso8601(purchase.purchaseTime),
            developerPayload = purchase.developerPayload,
            subscriptionToken = purchase.subscriptionToken,
            sandbox = purchase.sandbox,
        )
    }

    private fun mapPaymentResult(
        result: PaymentResult,
        requestedPurchaseType: RustorePurchaseType,
    ): RustoreProductPurchaseResult {
        return when (result) {
            is PaymentResult.Success -> RustoreProductPurchaseResult(
                resultType = RustoreProductPurchaseResultType.SUCCESS,
                purchase = RustorePurchase(
                    purchaseId = result.purchaseId,
                    purchaseType = requestedPurchaseType,
                    productType = RustoreProductType.UNKNOWN,
                    purchaseStatus = RustorePurchaseStatus.CONFIRMED,
                    productId = result.productId,
                    invoiceId = result.invoiceId,
                    orderId = result.orderId,
                    subscriptionToken = result.subscriptionToken,
                    sandbox = result.sandbox,
                ),
            )
            is PaymentResult.Cancelled -> RustoreProductPurchaseResult(
                resultType = RustoreProductPurchaseResultType.CANCELLED,
                purchase = RustorePurchase(
                    purchaseId = result.purchaseId,
                    purchaseType = requestedPurchaseType,
                    productType = RustoreProductType.UNKNOWN,
                    purchaseStatus = RustorePurchaseStatus.CANCELLED,
                    sandbox = result.sandbox,
                ),
                error = RustorePurchaseError(
                    code = "PURCHASE_CANCELLED",
                    message = "Purchase cancelled by user",
                ),
            )
            is PaymentResult.Failure -> RustoreProductPurchaseResult(
                resultType = RustoreProductPurchaseResultType.FAILURE,
                purchase = RustorePurchase(
                    purchaseId = result.purchaseId ?: "",
                    purchaseType = requestedPurchaseType,
                    productType = RustoreProductType.UNKNOWN,
                    purchaseStatus = RustorePurchaseStatus.CANCELLED,
                    productId = result.productId,
                    invoiceId = result.invoiceId,
                    orderId = result.orderId,
                    sandbox = result.sandbox,
                ),
                error = RustorePurchaseError(
                    code = "PURCHASE_FAILURE",
                    message = "Purchase failed",
                ),
            )
            is PaymentResult.InvalidPaymentState -> RustoreProductPurchaseResult(
                resultType = RustoreProductPurchaseResultType.FAILURE,
                error = RustorePurchaseError(
                    code = "INVALID_PAYMENT_STATE",
                    message = "Invalid payment state",
                ),
            )
            else -> RustoreProductPurchaseResult(
                resultType = RustoreProductPurchaseResultType.UNKNOWN,
            )
        }
    }

    private fun mapPurchaseThrowable(error: Throwable): RustorePurchaseError {
        return RustorePurchaseError(
            code = error.javaClass.simpleName,
            message = error.message ?: "Purchase failed",
            description = error.toString(),
        )
    }

    private fun mapException(error: Throwable): RustoreException {
        val type = when (error) {
            is RuStoreNotInstalledException -> RustoreExceptionType.NOT_INSTALLED
            is RuStoreOutdatedException -> RustoreExceptionType.OUTDATED
            is RuStoreUserUnauthorizedException -> RustoreExceptionType.USER_UNAUTHORIZED
            is RuStoreException -> RustoreExceptionType.GENERAL
            else -> RustoreExceptionType.UNKNOWN
        }
        return RustoreException(
            type = type,
            message = error.message ?: "Unknown error",
            errorCode = error.javaClass.simpleName,
        )
    }

    private fun mapProductType(productType: ProductType?): RustoreProductType {
        return when (productType) {
            ProductType.CONSUMABLE -> RustoreProductType.CONSUMABLE
            ProductType.NON_CONSUMABLE -> RustoreProductType.NON_CONSUMABLE
            ProductType.SUBSCRIPTION -> RustoreProductType.SUBSCRIPTION
            null -> RustoreProductType.UNKNOWN
        }
    }

    private fun mapProductStatus(productStatus: ProductStatus?): RustoreProductStatus {
        return when (productStatus) {
            ProductStatus.ACTIVE -> RustoreProductStatus.ACTIVE
            ProductStatus.INACTIVE -> RustoreProductStatus.INACTIVE
            null -> RustoreProductStatus.UNKNOWN
        }
    }

    private fun mapPurchaseStatus(purchaseState: PurchaseState?): RustorePurchaseStatus {
        return when (purchaseState) {
            PurchaseState.CREATED -> RustorePurchaseStatus.CREATED
            PurchaseState.INVOICE_CREATED -> RustorePurchaseStatus.INVOICE_CREATED
            PurchaseState.PAID -> RustorePurchaseStatus.PAID
            PurchaseState.CONFIRMED -> RustorePurchaseStatus.CONFIRMED
            PurchaseState.CANCELLED -> RustorePurchaseStatus.CANCELLED
            PurchaseState.CONSUMED -> RustorePurchaseStatus.CONSUMED
            PurchaseState.CLOSED -> RustorePurchaseStatus.CLOSED
            PurchaseState.PAUSED -> RustorePurchaseStatus.PAUSED
            PurchaseState.TERMINATED -> RustorePurchaseStatus.TERMINATED
            null -> RustorePurchaseStatus.UNKNOWN
        }
    }

    private fun inferPurchaseType(purchaseState: PurchaseState?): RustorePurchaseType {
        return when (purchaseState) {
            PurchaseState.CREATED,
            PurchaseState.INVOICE_CREATED,
            PurchaseState.PAID,
            -> RustorePurchaseType.TWO_STEP
            PurchaseState.CONFIRMED,
            PurchaseState.CONSUMED,
            PurchaseState.CANCELLED,
            PurchaseState.CLOSED,
            PurchaseState.PAUSED,
            PurchaseState.TERMINATED,
            -> RustorePurchaseType.ONE_STEP
            null -> RustorePurchaseType.UNKNOWN
        }
    }

    private fun mapThemeToSdk(theme: RustoreBillingTheme): BillingClientTheme {
        return when (theme) {
            RustoreBillingTheme.DARK -> BillingClientTheme.Dark
            RustoreBillingTheme.LIGHT -> BillingClientTheme.Light
            RustoreBillingTheme.SYSTEM -> BillingClientTheme.Light
            RustoreBillingTheme.UNKNOWN -> BillingClientTheme.Light
        }
    }

    private fun matchesFilter(
        purchase: RustorePurchase,
        filter: RustorePurchaseFilter?,
    ): Boolean {
        if (filter == null) {
            return true
        }
        if (filter.productId != null && filter.productId != purchase.productId) {
            return false
        }
        if (filter.productType != null && filter.productType != purchase.productType) {
            return false
        }
        if (filter.purchaseStatus != null && filter.purchaseStatus != purchase.purchaseStatus) {
            return false
        }
        if (filter.purchaseType != null && filter.purchaseType != purchase.purchaseType) {
            return false
        }
        return true
    }
}

private class StaticBillingThemeProvider(
    private val theme: BillingClientTheme,
) : BillingClientThemeProvider {
    override fun provide(): BillingClientTheme = theme
}

private fun SubscriptionPeriod.toIsoDuration(): String {
    return "P${years}Y${months}M${days}D"
}

private fun formatDateToIso8601(date: java.util.Date?): String? {
    if (date == null) {
        return null
    }
    val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
    formatter.timeZone = TimeZone.getTimeZone("UTC")
    return formatter.format(date)
}

private fun RustorePreferredPurchaseType.toPurchaseType(): RustorePurchaseType {
    return when (this) {
        RustorePreferredPurchaseType.ONE_STEP -> RustorePurchaseType.ONE_STEP
        RustorePreferredPurchaseType.TWO_STEP -> RustorePurchaseType.TWO_STEP
        RustorePreferredPurchaseType.UNKNOWN -> RustorePurchaseType.UNKNOWN
    }
}
