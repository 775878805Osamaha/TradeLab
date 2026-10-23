package com.example.feature.settings

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.example.R
import com.example.TradeLabApplication
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
internal fun HistorySettingsCard() {
    val app = LocalContext.current.applicationContext as TradeLabApplication
    var input by remember { mutableStateOf("") }
    var configured by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<Int?>(null) }
    val scope = rememberCoroutineScope()
    LaunchedEffect(Unit) { configured = withContext(Dispatchers.IO) { app.historyKeyStore.read().isNotBlank() } }
    fun save(value: String) {
        saving = true
        scope.launch {
            message = try {
                withContext(Dispatchers.IO) {
                    app.historyKeyStore.save(value)
                    app.marketDataRepository.configureTwelveDataKey(value)
                }
                configured = value.isNotBlank()
                input = ""
                if (configured) R.string.history_saved else R.string.history_removed
            } catch (_: Exception) { R.string.history_save_error }
            saving = false
        }
    }
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(stringResource(R.string.history_title), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.history_help), style = MaterialTheme.typography.bodySmall)
            if (configured) Text(stringResource(R.string.history_configured))
            OutlinedTextField(value = input, onValueChange = { input = it }, singleLine = true,
                visualTransformation = PasswordVisualTransformation(), enabled = !saving,
                label = { Text(stringResource(R.string.history_key_label)) }, modifier = Modifier.fillMaxWidth())
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { save(input.trim()) }, enabled = !saving && input.isNotBlank()) {
                    Text(stringResource(R.string.history_save))
                }
                TextButton(onClick = { save("") }, enabled = !saving && configured) {
                    Text(stringResource(R.string.history_remove))
                }
            }
            message?.let { Text(stringResource(it)) }
            Text(stringResource(R.string.history_disclosure), style = MaterialTheme.typography.bodySmall)
        }
    }
}
