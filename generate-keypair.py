import subprocess
import json

# Function to generate keypair using fastcrypto
def generate_keypair(seed):
    keygen_command = f"./target/debug/sigs-cli keygen --scheme bls12381-minpk --seed {seed}"
    process = subprocess.Popen(keygen_command.split(), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output, error = process.communicate()


    # Check if there is any error
    if error:
        print(f"Error during key generation: {error.decode('utf-8')}")
        return None

    # Decode the output
    output_decoded = output.decode("utf-8")
    
    print(f"Key generation output: {output_decoded}")
    # Parse the private and public key from the output
    private_key = None
    public_key = None
    
    for line in output_decoded.splitlines():
        if "Private key in hex" in line:
            private_key = line.split(": ")[1].strip()
        elif "Public key in hex" in line:
            public_key = line.split(": ")[1].strip()

    if not private_key or not public_key:
        print("Failed to parse keys from output.")
        return None

    return private_key, public_key


# Main workflow
if __name__ == "__main__":
    # You can set a seed here (must be 32 bytes)
    seed = "0000000000000000000000000532000000000000000000000000000000000000"
    
    # Step 1: Generate keypair
    private_key, public_key = generate_keypair(seed)
    if private_key and public_key:
        print(f"Private Key: {private_key}")
        print(f"Public Key: {public_key}")

        # Step 2: Store the keys in a JSON file for later use
        key_data = {
            "private_key": private_key,
            "public_key": public_key
        }

        with open("keypair.json", "w") as key_file:
            json.dump(key_data, key_file)

        print("Keypair saved to keypair.json")
    else:
        print("Keypair generation failed.")
