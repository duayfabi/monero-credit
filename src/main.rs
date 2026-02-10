mod gotify;

use dotenvy::dotenv;
use gotify::GotifyClient;
use reqwest::blocking::Client;
use reqwest::header::USER_AGENT;
use std::env;
use std::io::Read;

#[allow(non_snake_case)]
#[derive(serde::Deserialize)]
struct MoneroResponse {
    amtDue: u64,
}

fn fill_template(template: &str, due_amount: u64) -> String {
    let due_amount = due_amount as f64 / 1_000_000_000_000.0; // Convertir de piconero à monero

    template.replace("{due_amount}", &format!("{:.5}", due_amount))
}

fn gotify_send_notification(
    gotify_client: &GotifyClient,
    title: &str,
    message: &str,
    priority: Option<u8>,
) {
    let priority = priority.unwrap_or(5);

    if let Err(e) = gotify_client.send_notification(title, message, priority) {
        eprintln!(
            "Avertissement : Impossible d'envoyer la notification Gotify : {}",
            e
        );
    }
}

fn get_due_amount(url: &str, user_agent: &str) -> Result<u64, Box<dyn std::error::Error>> {
    let client = Client::new();

    let mut response = client.get(url).header(USER_AGENT, user_agent).send()?;

    if response.status().is_success() {
        let mut buffer = String::new();
        response.read_to_string(&mut buffer)?;

        let response: MoneroResponse = serde_json::from_str(&buffer)?;

        return Ok(response.amtDue);
    }

    Err(format!("Erreur : {}", response.status()).into())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    rustls::crypto::ring::default_provider()
        .install_default()
        .expect("Failed to install rustls crypto provider");
    dotenv().ok();

    let monero_address =
        env::var("MONERO_ADDRESS").expect("Unable to find the MONERO_ADDRESS env variable");
    let url = format!(
        "https://api.moneroocean.stream/miner/{}/stats",
        monero_address
    );
    let user_agent = env::var("USER_AGENT").expect("Unable to find the USER_AGENT env variable");

    let gotify_client = GotifyClient::from_env();

    let mut error_msg = String::new();

    match get_due_amount(&url, &user_agent) {
        Ok(due_amount) => {
            let template = env::var("SUCCESS_MSG")
                .ok()
                .filter(|s| !s.trim().is_empty())
                .unwrap_or_else(|| "✅ {due_amount} XMR due amount".to_string());

            let success_msg = fill_template(&template, due_amount);
            println!("{}", success_msg);

            // Envoyer une notification de succès
            if let Some(ref client) = gotify_client {
                gotify_send_notification(client, "monero", &success_msg, None);
            }
        }
        Err(e) => {
            error_msg = format!("❌ Impossible de récupérer le montant dû : {}", e);
        }
    }

    if !error_msg.is_empty() {
        println!("{}", error_msg);

        if let Some(ref client) = gotify_client {
            gotify_send_notification(client, "monero", &error_msg, None);
        }
    }

    Ok(())
}
