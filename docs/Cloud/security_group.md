### In terraform spezzare in due file separati la sezione dei SG, un primo file SG.TF dove vengono definiti i vari security group, un secondo file SG-rules.tf dove si definiscono le regole. Usare intestazione con testo commentato per spezzare regole appartenenti ai differenti SG

## sg-waf (VM WAF)
Reverse proxy + ModSecurity, unico ingresso pubblico
Dir.	    Porta	    Origine / Destinazione	    Motivo
Ingress	    80	         0.0.0.0/0	                Traffico HTTP di utenti e Red Team
Ingress	    443	         0.0.0.0/0	                Traffico HTTPS di utenti e Red Team
Ingress 	22	         sg-bastion	                Amministrazione via bastion
Egress	    3000  	     sg-app	                    Inoltro delle richieste a Juice Shop
Egress  	1514     	 sg-wazuh	                Invio eventi/log dell’agent
Egress  	1515	     sg-wazuh	                Registrazione dell’agent sul manager
Egress  	80, 443	     0.0.0.0/0 (via IGW)	        apt, repository Wazuh/ModSecurity

## sg-bastion (VM bastion host)
Unico accesso amministrativo per Blue Team e team Cloud
Dir.	    Porta	    Origine / Destinazione	    Motivo
Ingress	    22	        IP del team (CIDR /32)	    Accesso SSH dall’esterno
Egress	    22	        sg-waf                  	SSH / ProxyJump verso il WAF
Egress	    22	        sg-app	                    SSH / ProxyJump verso Juice Shop
Egress	    22	        sg-wazuh	                SSH / ProxyJump verso Wazuh
Egress	    443	        sg-wazuh	                Dashboard Wazuh (opzionale, solo con forward dal bastion)
Egress  	80, 443	    0.0.0.0/0 (via IGW)	        Aggiornamenti e pacchetti

## sg-app ( VM JuiceShop)
Applicazione vulnerabile, raggiungibile solo da WAF
Dir.	    Porta	    Origine / Destinazione	    Motivo
Ingress	    3000	    sg-waf	                    Richieste inoltrate dal reverse proxy
Ingress	    22	        sg-bastion	                Amministrazione via bastion
Egress	    1514	    sg-wazuh	                Invio eventi/log dell’agent
Egress	    1515	    sg-wazuh	                Registrazione dell’agent
Egress	    80, 443	    0.0.0.0/0 (via NAT)	        apt, pull immagine Docker

## sg-wazuh (VM SIEM)
Manager, indexer e Dashboard, raccolta log centralizzata.
Dir.	    Porta	    Origine / Destinazione	    Motivo
Ingress	    1514	    sg-waf, sg-app	            Ricezione log dagli agent (una regola per sorgente)
Ingress 	1515	    sg-waf, sg-app	            Registrazione degli agent (una regola per sorgente)
Ingress	    22	        sg-bastion  	            Amministrazione via bastion
Ingress	    443	        sg-bastion	                Dashboard (opzionale, come sopra)
Egress	    80, 443 	0.0.0.0/0 (via NAT)     	apt, repository e feed di vulnerabilità Wazuh


# Note



