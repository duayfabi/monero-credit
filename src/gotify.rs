use std::env;

#[derive(Debug, Clone)]
pub struct GotifyClient {
    url: String,
    token: String,
}

impl GotifyClient {
    /// Crée un client Gotify à partir des variables d'environnement
    /// Retourne None si GOTIFY_URL ou GOTIFY_TOKEN ne sont pas définis
    pub fn from_env() -> Option<Self> {
        let url = env::var("GOTIFY_URL").ok()?;
        let token = env::var("GOTIFY_TOKEN").ok()?;

        Some(GotifyClient { url, token })
    }

    /// Envoie une notification au serveur Gotify
    ///
    /// # Arguments
    /// * `title` - Le titre de la notification
    /// * `message` - Le message de la notification
    /// * `priority` - La priorité (0-10, où 10 est le plus prioritaire)
    pub fn send_notification(
        &self,
        title: &str,
        message: &str,
        priority: u8,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let client = reqwest::blocking::Client::builder()
            .timeout(std::time::Duration::from_secs(5))
            .build()?;

        let base_url = self.url.trim_end_matches('/');
        let url = format!("{}/message", base_url);

        let payload = serde_json::json!({
            "title": title,
            "message": message,
            "priority": priority,
        });

        let response = client
            .post(&url)
            .header("X-Gotify-Key", &self.token)
            .header("Content-Type", "application/json")
            .json(&payload)
            .send()?;

        if !response.status().is_success() {
            let status = response.status();
            let error_msg = response.text().unwrap_or_else(|_| "Pas de détails".into());
            return Err(format!("Gotify erreur {} : {}", status, error_msg).into());
        }

        Ok(())
    }
}
