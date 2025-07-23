package com.xsoulspace.rustore_billing_api

import android.app.Activity
import android.content.Context
import android.content.Intent
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import ru.rustore.sdk.billingclient.RuStoreBillingClient
import ru.rustore.sdk.billingclient.RuStoreBillingClientFactory
import ru.rustore.sdk.billingclient.model.product.Product
import ru.rustore.sdk.billingclient.model.purchase.PaymentResult
import ru.rustore.sdk.billingclient.model.purchase.Purchase
import ru.rustore.sdk.billingclient.model.purchase.PurchaseState
import io.flutter.plugin.common.MethodChannel
import ru.rustore.sdk.billingclient.model.purchase.PurchaseAvailabilityResult
import ru.rustore.sdk.billingclient.presentation.BillingClientTheme
import ru.rustore.sdk.billingclient.provider.BillingClientThemeProvider
import ru.rustore.sdk.billingclient.utils.pub.checkPurchasesAvailability

/** RustoreBillingApiPlugin */
class RustoreBillingApiPlugin: FlutterPlugin, ActivityAware, RustoreBillingApi {
    private var context: Context? = null
    private var activity: Activity? = null
    private var billingClient: RuStoreBillingClient? = null
    private var callbackApi: RustoreBillingCallbackApi? = null
    private val coroutineScope = CoroutineScope(Dispatchers.Main)

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        RustoreBillingApi.setUp(flutterPluginBinding.binaryMessenger, this)
        callbackApi = RustoreBillingCallbackApi(flutterPluginBinding.binaryMessenger)
        
        // Register the Android implementation
        val channel = MethodChannel(flutterPluginBinding.binaryMessenger, "rustore_billing_api")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "registerWith" -> {
                    // This will be handled by the Dart side
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        RustoreBillingApi.setUp(binding.binaryMessenger, null)
        context = null
        callbackApi = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun initialize(config: RustoreBillingConfig, callback: (Result<Unit>) -> Unit) {
        try {
            val appContext = context ?: throw IllegalStateException("Plugin not attached to context")
            
            billingClient = RuStoreBillingClientFactory.create(
                context = appContext,
                consoleApplicationId = config.consoleApplicationId,
                deeplinkScheme = config.deeplinkScheme,
                debugLogs = config.debugLogs,
                themeProvider = BillingClientThemeProviderImpl(
                    config
                ),
                externalPaymentLoggerFactory = if (config.enableLogging) {
                    { tag ->
                        object : ru.rustore.sdk.billingclient.model.logging.ExternalPaymentLogger {
                            override fun d(e: Throwable?, message: () -> String) {
                                android.util.Log.d(tag, message.invoke(), e)
                            }
                            override fun e(e: Throwable?, message: () -> String) {
                                android.util.Log.e(tag, message.invoke(), e)
                            }
                            override fun i(e: Throwable?, message: () -> String) {
                                android.util.Log.i(tag, message.invoke(), e)
                            }
                            override fun v(e: Throwable?, message: () -> String) {
                                android.util.Log.v(tag, message.invoke(), e)
                            }
                            override fun w(e: Throwable?, message: () -> String) {
                                android.util.Log.w(tag, message.invoke(), e)
                            }
                        }
                    }
                } else null
            )
            
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun onNewIntent(intentData: String?) {
        val client = billingClient ?: return
        
        // Parse intent data if needed, for now pass null
        // In real implementation, you'd reconstruct Intent from intentData
        client.onNewIntent(null)
    }

    override fun checkPurchasesAvailability(callback: (Result<RustorePurchaseAvailabilityResult>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        coroutineScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    RuStoreBillingClient.checkPurchasesAvailability().await()
                }

                val rustoreResult = when (result) {
                    is Available -> RustorePurchaseAvailabilityResult(
                        resultType = RustorePurchaseAvailabilityType.AVAILABLE,
                        cause = null
                    )
                    is Unavailable -> RustorePurchaseAvailabilityResult(
                        resultType = RustorePurchaseAvailabilityType.UNAVAILABLE,
                        cause = mapException(result.cause)
                    )
                    is Unknown -> RustorePurchaseAvailabilityResult(
                        resultType = RustorePurchaseAvailabilityType.UNKNOWN,
                        cause = mapException(result.cause)
                    )

                    PurchaseAvailabilityResult.Available -> TODO()
                    is PurchaseAvailabilityResult.Unavailable -> TODO()
                    PurchaseAvailabilityResult.Unknown -> TODO()
                }

                callback(Result.success(rustoreResult))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun isRuStoreInstalled(callback: (Result<Boolean>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        coroutineScope.launch {
            try {
                val isInstalled = withContext(Dispatchers.IO) {
                    RuStoreBillingClient.isRuStoreInstalled()
                }
                
                callback(Result.success(isInstalled))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getProducts(productIds: List<String>, callback: (Result<List<RustoreProduct>>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        coroutineScope.launch {
            try {
                val products = withContext(Dispatchers.IO) {
                    client.products.getProducts(productIds).await()
                }
                
                val rustoreProducts = products.map { product ->
                    RustoreProduct(
                        productId = product.productId,
                        productType = product.productType ?: "",
                        title = product.title,
                        description = product.description,
                        price = product.price?.toLong(),
                        priceLabel = product.priceLabel,
                        currency = product.currency,
                        language = product.language
                    )
                }
                
                callback(Result.success(rustoreProducts))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getPurchases(callback: (Result<List<RustorePurchase>>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        coroutineScope.launch {
            try {
                val purchases = withContext(Dispatchers.IO) {
                    client.purchases.getPurchases().await()
                }
                
                val rustorePurchases = purchases.map { purchase ->
                    RustorePurchase(
                        purchaseId = purchase.purchaseId,
                        productId = purchase.productId,
                        invoiceId = purchase.invoiceId,
                        description = purchase.description,
                        language = purchase.language,
                        purchaseTime = purchase.purchaseTime,
                        orderId = purchase.orderId,
                        amountLabel = purchase.amountLabel,
                        amount = purchase.amount?.toLong(),
                        currency = purchase.currency,
                        quantity = purchase.quantity?.toLong(),
                        purchaseState = mapPurchaseState(purchase.purchaseState),
                        developerPayload = purchase.developerPayload
                    )
                }
                
                callback(Result.success(rustorePurchases))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun purchaseProduct(productId: String, developerPayload: String?, callback: (Result<RustorePaymentResult>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        client.purchases.purchaseProduct(
            productId = productId,
            developerPayload = developerPayload
        )
        .addOnSuccessListener { paymentResult ->
            val result = mapPaymentResult(paymentResult)
            callback(Result.success(result))
            
            // Also notify via callback API
            callbackApi?.onPurchaseResult(result) {}
        }
        .addOnFailureListener { throwable ->
            val error = RustoreError(
                code = throwable::class.java.simpleName,
                message = throwable.message ?: "Unknown error",
                description = throwable.toString()
            )
            
            callback(Result.failure(throwable))
            callbackApi?.onError(error) {}
        }
    }

    override fun confirmPurchase(purchaseId: String, developerPayload: String?, callback: (Result<Unit>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        client.purchases.confirmPurchase(purchaseId, developerPayload)
            .addOnSuccessListener {
                callback(Result.success(Unit))
            }
            .addOnFailureListener { throwable ->
                callback(Result.failure(throwable))
            }
    }

    override fun deletePurchase(purchaseId: String, callback: (Result<Unit>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        client.purchases.deletePurchase(purchaseId)
            .addOnSuccessListener {
                callback(Result.success(Unit))
            }
            .addOnFailureListener { throwable ->
                callback(Result.failure(throwable))
            }
    }

    override fun setTheme(theme: RustoreBillingTheme, callback: (Result<Unit>) -> Unit) {
        val client = billingClient
        if (client == null) {
            callback(Result.failure(IllegalStateException("Billing client not initialized")))
            return
        }

        try {
            val billingTheme = when (theme) {
                RustoreBillingTheme.LIGHT -> Light
                RustoreBillingTheme.DARK -> Dark
            }
            
            // Note: The actual theme setting might require recreating the client
            // or using a different approach depending on the RuStore SDK
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    private fun mapPurchaseState(state: PurchaseState?): RustorePurchaseState? {
        return when (state) {
            PurchaseState.CREATED -> RustorePurchaseState.CREATED
            PurchaseState.INVOICE_CREATED -> RustorePurchaseState.INVOICE_CREATED
            PurchaseState.CONFIRMED -> RustorePurchaseState.CONFIRMED
            PurchaseState.PAID -> RustorePurchaseState.PAID
            PurchaseState.CANCELLED -> RustorePurchaseState.CANCELLED
            PurchaseState.CONSUMED -> RustorePurchaseState.CONSUMED
            PurchaseState.CLOSED -> RustorePurchaseState.CLOSED
            null -> null
        }
    }

    private fun mapPaymentResult(result: PaymentResult): RustorePaymentResult {
        return when (result) {
            is PaymentResult.Success -> RustorePaymentResult(
                resultType = RustorePaymentResultType.SUCCESS,
                purchaseId = result.purchaseId,
                errorCode = null,
                errorMessage = null
            )
            is PaymentResult.Cancelled -> RustorePaymentResult(
                resultType = RustorePaymentResultType.CANCELLED,
                purchaseId = null,
                errorCode = null,
                errorMessage = "Payment cancelled"
            )
            is PaymentResult.Failure -> RustorePaymentResult(
                resultType = RustorePaymentResultType.FAILURE,
                purchaseId = null,
                errorCode = result.purchaseId, // This might contain error info
                errorMessage = "Payment failed"
            )
            is PaymentResult.InvalidPaymentState -> RustorePaymentResult(
                resultType = RustorePaymentResultType.INVALID_PAYMENT_STATE,
                purchaseId = null,
                errorCode = null,
                errorMessage = "Invalid payment state"
            )
        }
    }

    private fun mapException(exception: ru.rustore.sdk.billingclient.model.exception.RuStoreException?): RustoreException? {
        if (exception == null) return null
        
        val exceptionType = when (exception) {
            is ru.rustore.sdk.billingclient.model.exception.RuStoreNotInstalledException -> RustoreExceptionType.NOT_INSTALLED
            is ru.rustore.sdk.billingclient.model.exception.RuStoreOutdatedException -> RustoreExceptionType.OUTDATED
            is ru.rustore.sdk.billingclient.model.exception.RuStoreUserUnauthorizedException -> RustoreExceptionType.USER_UNAUTHORIZED
            is ru.rustore.sdk.billingclient.model.exception.RuStoreRequestLimitReached -> RustoreExceptionType.REQUEST_LIMIT_REACHED
            is ru.rustore.sdk.billingclient.model.exception.RuStoreReviewExists -> RustoreExceptionType.REVIEW_EXISTS
            is ru.rustore.sdk.billingclient.model.exception.RuStoreInvalidReviewInfo -> RustoreExceptionType.INVALID_REVIEW_INFO
            else -> RustoreExceptionType.GENERAL
        }
        
        return RustoreException(
            type = exceptionType,
            message = exception.message ?: "Unknown error",
            errorCode = exception.errorCode
        )
    }
}




class BillingClientThemeProviderImpl: BillingClientThemeProvider {
    BillingClientThemeProviderImpl(RustoreBillingConfig config)

    override fun provide(): BillingClientTheme {

        if(darkTheme){
            BillingClientTheme.Dark
        } else {
            BillingClientTheme.Light
        }
    }
}