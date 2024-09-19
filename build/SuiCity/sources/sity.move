
module suicity::nft {
  // === Imports ===
    use sui::url::{Self, Url};
    use std::string;
    use sui::event;
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin, TreasuryCap};
    use suicity::sity::{Self,SITY};
    use sui::table::{Self, Table};
    use sui::package;
    use sui::display;
    use sui::ed25519;

  // === Errors ===
    const ENotPublisher: u64 = 0;
    const ENotUpgrade: u64 = 1;
    const EWrongVersion: u64 = 2;
    const EAlreadyMinted: u64 = 3;
    const EInsufficientBalance: u64 = 4;
    const EInvalidBuildingType: u64 = 5;
    const EInvalidTokenType: u64 = 6;
    const EZeroBalance : u64 = 7;
    const ENotEnoughTime : u64 = 8;

  // === Constants ===
    const VERSION: u64 = 1;

  // === Structs ===
    public struct NFT has drop {}

    public struct City has key  {
        id: UID,
        /// Name for the token
        name: string::String,
        /// Description of the token
        description: string::String,
        /// URL for the token
        url: Url,

        balance: Balance<SITY>,

        // buildings
        buildings: vector<u64>,  // Building levels stored in a vector


        /// Timestamp of the last SITY claim
        last_claimed: u64,

        /// Timestamp of the last SITY claim
        last_daily_bonus: u64,

        last_accumulated: u64,
    
        population: u64,

        ref_used : bool,
    }

    public struct GameData has key {
        id: UID,                
        version: u64,
        minted: u64,
        speed: u64,  
        cost_multiplier: u64,                       // Number of NFTs minted so far
        base_name: string::String,    // Base name for the NFTs
        base_url: string::String,     // Base URL for the NFTs
        base_image_url: string::String, // Base image URL for the NFTs
        description: string::String,  // Description of the NFTs
        balance: Balance<SUI>,   // Balance for storing funds from NFT upgrades
        pool: Balance<SITY>,   // Balance for storing funds from NFT upgrades
        publisher: address,      // Address of the publisher
        accumulation_speeds: vector<u64>,   // Store accumulation speeds
        sui_costs: vector<vector<u64>>,     // SUI costs for each building level
        sity_costs: vector<vector<u64>>,  
        factory_bonuses: vector<u64>,
        minted_users: Table<address, MintedByUser>,  // Using Table for efficient lookups

        public_key: vector<u8>, // Public key for verifying backend-signed messages
        ref_reward: u64,
        

    }
    public struct MintedByUser has store, drop {
    user_minted: bool,  // Tracks if the user has minted an NFT (true if minted, false otherwise)
    }
    public struct SITYClaimed has copy, drop {
        // The Object ID of the NFT
        nft_id: ID,
        // The creator of the NFT
        amount: u64,
        // The name of the NFT
        claimer: address,
        }
    // ===== Events =====

    public struct NFTMinted has copy, drop {
        // The Object ID of the NFT
        object_id: ID,
        // The creator of the NFT
        creator: address,
        // The name of the NFT
        name: string::String,
        }

    public struct BonusClaimed has copy, drop {
        // The Object ID of the NFT
        object_id: ID,
        // The creator of the NFT
        amount: u64,
        }

        public struct RewardClaimed has copy, drop {
        // The Object ID of the NFT
        claimer: address,
        // The creator of the NFT
        amount: u64,
        }

    /// Event to track NFT upgrades
    public struct NFTUpgraded has copy, drop {
        object_id: ID,
        building_type: u8,
        new_level: u64,
        }

     /// Event to track NFT upgrades
    public struct RefBonusClaimed has copy, drop {
        nft_id: ID,
        claimer: address,
        ref_owner: address,
        }

  // === Public-Mutative Functions ===

   public entry fun accumulate_sity(nft: &mut City, game: &mut GameData, clock: &sui::clock::Clock, ctx: &mut TxContext) {
        assert!(game.version == VERSION, EWrongVersion); // Ensure the game data version is correct
        let current_time = sui::clock::timestamp_ms(clock);
        let time_lapsed = (current_time - nft.last_accumulated) ;

        let time_lapsed_from_claim = (current_time - nft.last_claimed) ;

        let max_accumulation_period = calculate_max_accumulation(game, nft);

        let effective_time_lapsed :u64;

        if (time_lapsed_from_claim <= max_accumulation_period) {
            effective_time_lapsed = time_lapsed;
        } else {

            let already_accummulated = nft.last_accumulated - nft.last_claimed;
            if (already_accummulated >= max_accumulation_period) {
                effective_time_lapsed = 0;
            }
            else{
                if (already_accummulated >= 0) {
                effective_time_lapsed = max_accumulation_period - already_accummulated;
            }
            else{
                effective_time_lapsed = max_accumulation_period;
            }
            }

        };

        let residential_office = nft.buildings[0];  // Key `0` represents residential office.

        let accumulation_per_hour = game.accumulation_speeds[residential_office];
        let accumulated_sity_ms = (effective_time_lapsed * accumulation_per_hour * game.speed);
        let accumulated_sity = accumulated_sity_ms / 3600000;

        let reward = coin::take(&mut game.pool, accumulated_sity, ctx);
        balance::join(&mut nft.balance, coin::into_balance(reward));

        nft.last_accumulated = current_time;
        }

public entry fun claim_sity(nft: &mut City,game : &mut GameData, clock: &sui::clock::Clock, ctx: &mut TxContext) {

        // First, accumulate the SITY based on the time since the last claim
        accumulate_sity(nft, game, clock, ctx);

        let sender = tx_context::sender(ctx);

        // Get the balance of SITY tokens in the NFT
        let sity_balance = balance::value(&nft.balance);

        // Ensure that there is a non-zero balance to claim
        assert!(sity_balance > 0, EZeroBalance);

        // Take the SITY tokens from the NFT's balance
        let claimed_sity = coin::take(&mut nft.balance, sity_balance, ctx);

        // Transfer the claimed SITY tokens to the sender (user)
        transfer::public_transfer(claimed_sity, sender);

            event::emit(SITYClaimed {
            nft_id: object::uid_to_inner(&nft.id),
            amount: sity_balance,
            claimer: sender,
        });
        let current_time = sui::clock::timestamp_ms(clock);

        nft.last_claimed = current_time;

        }

/// Claim the daily production from the factory (with a fee)
    public entry fun claim_factory_bonus(nft: &mut City, game: &mut GameData, clock: &sui::clock::Clock, ctx: &mut TxContext) {

        accumulate_sity(nft, game, clock, ctx);
        let current_time = sui::clock::timestamp_ms(clock);

        // Ensure it's been 24 hours since the last claim
        let time_since_last_claim = current_time - nft.last_daily_bonus;
        assert!(time_since_last_claim >= (24 * 3600 * 1000) / game.speed, ENotEnoughTime); // 24 hours

        // Calculate the daily bonus based on the factory level
        let daily_bonus = calculate_factory_bonus( nft,game);
        let reward = coin::take(&mut game.pool, daily_bonus, ctx);

        nft.last_daily_bonus = current_time;

        transfer::public_transfer(reward, tx_context::sender(ctx));

        event::emit(BonusClaimed{
            object_id:object::id(nft),
            amount:daily_bonus
        });
        }

/// Function to claim rewards based on the backend-signed message
  public entry fun claim_reward(
      game: &mut GameData,
       sig: vector<u8>,          // Signature from the backend
       msg: vector<u8>,      // Signed message containing the user's wallet address and amount
      amount: u64,              // Amount of SITY to claim
      ctx: &mut TxContext       // Context for the transaction
  ) {
      // Step 1: Verify the signatu
      let is_valid_signature = ed25519::ed25519_verify(&sig, &game.public_key, &msg);
      assert!(is_valid_signature, 31); // Signature must be valid


      // Step 2: Check the claim amount
      assert!(amount > 0, 32); // Amount must be positive

      // Step 3: Check the game pool's balance
      let pool_balance = balance::value(&game.pool);
      assert!(pool_balance >= amount, 33); // Ensure the pool has enough SITY tokens

      // Step 4: Take the claimed amount from the game pool
      let claimed_sity = coin::take(&mut game.pool, amount, ctx);

      // Step 5: Transfer the claimed SITY to the user's wallet
      let claimer = tx_context::sender(ctx);
      transfer::public_transfer(claimed_sity, claimer);

      // Step 6: Emit an event for the SITY claim
      event::emit(RewardClaimed {
          claimer: claimer,
          amount: amount,
      });
  }

  /// Function to claim rewards based on the backend-signed message
  public entry fun claim_reference(
      game: &mut GameData,
      nft: &mut City,
      ref_owner: address,
       sig: vector<u8>,          // Signature from the backend
       msg: vector<u8>,      // Signed message containing the user's wallet address and amount
      ctx: &mut TxContext       // Context for the transaction
  ) {

    

      let total_building_level = nft.buildings[0] + nft.buildings[1] + nft.buildings[2] + nft.buildings[3];

      assert!(total_building_level >= 3, 35); // Total building level must be greater than or equal to 3
      
      assert!(nft.ref_used == false, 34); // Reference must not be used
      
      let is_valid_signature = ed25519::ed25519_verify(&sig, &game.public_key, &msg);
      assert!(is_valid_signature, 31); // Signature must be valid

      let amount = game.ref_reward;

      // Step 3: Check the game pool's balance
      let pool_balance = balance::value(&game.pool);
      assert!(pool_balance >= (2*amount), 33); // Ensure the pool has enough SITY tokens

      // Step 4: Take the claimed amount from the game pool
      let claimed_sity = coin::take(&mut game.pool, amount, ctx);

      // Step 5: Transfer the claimed SITY to the user's wallet
      let claimer = tx_context::sender(ctx);
      transfer::public_transfer(claimed_sity, claimer);

      let claimed_sity_for_ref_owner = coin::take(&mut game.pool, amount, ctx);

      transfer::public_transfer(claimed_sity_for_ref_owner, ref_owner);

       nft.ref_used = true;


     event::emit(RefBonusClaimed {
            nft_id: object::uid_to_inner(&nft.id),
            claimer: claimer,
            ref_owner: ref_owner,
        });

  }

public entry fun build_city(
        game: &mut GameData,
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
        ) {
        assert!(game.version == VERSION, EWrongVersion); // Ensure the game data version is correct

        let sender = ctx.sender();

        // Check if the sender has already minted an NFT
        if (table::contains(&game.minted_users, sender)) {
            assert!(false, EAlreadyMinted);  // User has already minted, throw error
        };

        // Construct the NFT name: [base_name] + " #" + mint number
        let mut nft_name = game.base_name;
        string::append(&mut nft_name, string::utf8(vector::singleton(32))); // Add a space (' ')
        string::append(&mut nft_name, string::utf8(vector::singleton(35))); // Add a '#' character
        let mint_number_str = u64_to_string(game.minted + 1);
        string::append(&mut nft_name, mint_number_str);

        // Construct the initial image URL: [base_image_url] + "0.png"
        let mut image_url = game.base_image_url;
        string::append(&mut image_url, string::utf8(vector::singleton(48))); // Add '0' character
        string::append(&mut image_url, string::utf8(vector::singleton(48))); // Add '0' character
        string::append(&mut image_url, string::utf8(vector::singleton(48))); // Add '0' character
        string::append(&mut image_url, string::utf8(vector::singleton(48))); // Add '0' character
        let mut png_extension = vector::empty<u8>();
        vector::push_back(&mut png_extension, 46); // ASCII for '.'
        vector::push_back(&mut png_extension, 119); // 'w'
        vector::push_back(&mut png_extension, 101); // 'e'
        vector::push_back(&mut png_extension, 98);  // 'b'
        vector::push_back(&mut png_extension, 112); // 'p'

        string::append(&mut image_url, string::utf8(png_extension));


        let reward_amount = 100000; // 100 $SITY tokens
        let reward = coin::take(&mut game.pool, reward_amount, ctx); // Take 100 SITY tokens
        let sity_balance = coin::into_balance(reward); // Convert the taken reward into a balance

        // Add the sender to the minted_users table
        let minted_user = MintedByUser { user_minted: true };
        table::add(&mut game.minted_users, sender, minted_user);




    // Create the NFT
    let nft = City {
        id: object::new(ctx),
        name: nft_name,
        description: game.description, // Directly use the description
        url: url::new_unsafe_from_bytes(string::into_bytes(image_url)),
        balance: sity_balance,
        buildings: vector[0,0,0,0],  // Store the Table in the City struct

        

        last_claimed: sui::clock::timestamp_ms(clock),
        last_daily_bonus: sui::clock::timestamp_ms(clock) - (24 * 3600 * 1000), // Set to 24 hours ago
        last_accumulated: sui::clock::timestamp_ms(clock),
        population: 40000,
        ref_used    : false,
        };



    // Emit an event
    event::emit(NFTMinted {
        object_id: object::id(&nft),
        creator: sender,
        name: nft.name,
        });

        // Transfer the NFT to the sender
        transfer::transfer(nft, sender);


        // Increment the minted count in GameData
        game.minted = game.minted + 1;
        }

        public fun calculate_population(nft: &City): u64 {

        let mut population_res = 10000;
        let mut i = 0;
        while (i < nft.buildings[0]) {
            population_res = population_res * 14 / 10; // Multiply by 1.4
            i = i + 1;
        };

        let mut population_house = 10000;
        let mut j = 0;
        while (j < nft.buildings[1]) {
            population_house = population_house * 14 / 10; // Multiply by 1.4
            j = j + 1;
        };

        let mut population_factory = 10000;
        let mut k = 0;
        while (k < nft.buildings[2]) {
            population_factory = population_factory * 14 / 10; // Multiply by 1.4
            k = k + 1;
        };

        let mut population_entertainment = 10000;
        let mut l = 0;
        while (l < nft.buildings[3]) {
            population_entertainment = population_entertainment * 14 / 10; // Multiply by 1.4
            l = l + 1;
        };



        population_res + population_house + population_factory + population_entertainment + nft.balance.value()
        }

        /// Upgrade a building using SUI
    public fun upgrade_building_with_sui(
        nft: &mut City,
        game: &mut GameData,
        building_type: u8, // 1: Residential Office, 2: Factory, 3: House, 4: Entertainment Complex
        sui: Coin<SUI>,    // SUI coin to be used for the upgrade
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
        ) {
        accumulate_sity(nft, game, clock, ctx);

        let current_level = nft.buildings[building_type as u64];  // Key `0` represents residential office.

        let index = building_type as u64;
        // Fetch the correct SUI cost for the building and level from GameData
        let sui_cost = game.sui_costs[index][current_level] * game.cost_multiplier;
        let adjusted_sui_cost = sui_cost / 100;
        assert!(sui_cost!=0, EInvalidTokenType);

        // Check that the passed SUI amount matches the required cost
        let sui_value = coin::value(&sui);
        assert!(sui_value >= adjusted_sui_cost, EInsufficientBalance); // Ensure the correct SUI amount is passed


        // Add the SUI coin to the game balance
        balance::join(&mut game.balance, coin::into_balance(sui));

        let building_ref = vector::borrow_mut(&mut nft.buildings, building_type as u64);
        *building_ref = current_level + 1;

        let new_population = calculate_population(nft);
        nft.population = new_population;

        // Update the NFT's URL based on the new levels of the buildings
        let new_image_url = generate_image_url(
            &game.base_image_url,
            nft.buildings[0] ,
            nft.buildings[1],
            nft.buildings[2],
            nft.buildings[3]
        );
        nft.url = url::new_unsafe_from_bytes(string::into_bytes(new_image_url));

        // Emit an upgrade event (can use existing logic)

        event::emit(NFTUpgraded {
                object_id: object::uid_to_inner(&nft.id),
                building_type: building_type,
                new_level: current_level +1,
            });
        }

        /// Upgrade a building using SITY
        public fun upgrade_building_with_sity(
        nft: &mut City,
        game: &mut GameData,
        building_type: u8, // 1: Residential Office, 2: Factory, 3: House, 4: Entertainment Complex
        sity: Coin<SITY>,  // SITY coin to be used for the upgradfe
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
        ) {
        accumulate_sity(nft, game, clock, ctx);

        let current_level = nft.buildings[building_type as u64];  // Key `0` represents residential office.


        let index = building_type as u64;


        // Fetch the correct SITY cost for the building and level from GameData
        let sity_cost = game.sity_costs[index][current_level]* game.cost_multiplier;
        assert!(sity_cost!=0,EInvalidTokenType);

        let adjusted_sity_cost = sity_cost / 100;

        // Check that the passed SITY amount matches the required cost
        let sity_value = coin::value(&sity);
        assert!(sity_value >= adjusted_sity_cost, EInsufficientBalance); // Ensure the correct SITY amount is passed

        // Add the SITY coin to the game pool
        balance::join(&mut game.pool, coin::into_balance(sity));

        let building_ref = vector::borrow_mut(&mut nft.buildings, building_type as u64);
        *building_ref = current_level + 1;

        let new_population = calculate_population(nft);
        nft.population = new_population;

         // Update the NFT's URL based on the new levels of the buildings
        let new_image_url = generate_image_url(
            &game.base_image_url,
            nft.buildings[0] ,
            nft.buildings[1],
            nft.buildings[2],
            nft.buildings[3]
        );
        nft.url = url::new_unsafe_from_bytes(string::into_bytes(new_image_url));


        event::emit(NFTUpgraded {
            object_id: object::uid_to_inner(&nft.id),
            building_type: building_type,
            new_level: current_level +1,
        });
        
}


    /// Permanently delete `nft`
    public entry fun burn(nft: City, _: &mut TxContext) {
        let City { id, name: _, description: _, url: _, balance:bal,buildings: _, last_claimed: _, last_daily_bonus:_, last_accumulated: _, population : _, ref_used: _} = nft;
        balance::destroy_zero(bal);
        id.delete()
        }


    // ===== Public view functions =====

    /// Get the NFT's `name`
    public fun name(nft: &City): &string::String {
        &nft.name
        }

    /// Get the NFT's `description`
    public fun description(nft: &City): &string::String {
        &nft.description
        }

    /// Get the NFT's `url`
    public fun url(nft: &City): &Url {
        &nft.url
        }
    



  // === Admin Functions ===

    fun init(otw: NFT, ctx: &mut TxContext) {
        // The publisher is the account that published the package
        let publisher_address = tx_context::sender(ctx);

        let accumulation_speeds = vector[100000, 180000, 310000, 550000, 960000, 1700000, 3000000, 5125000];

        let sui_costs = vector[
        vector[1000000000, 0, 5000000000, 0, 25000000000, 0, 100000000000],         // SUI costs for Residential Office / House
        vector[0, 2250000000, 0, 12000000000, 0, 50000000000, 0], // SUI costs for Factory / Entertainment Complex
        vector[1000000000, 0, 5000000000, 0, 25000000000, 0, 100000000000],         // SUI costs for House (same as Residential Office)
        vector[0, 2250000000, 0, 12000000000, 0, 50000000000, 0] // SUI costs for Entertainment Complex (same as Factory)
        ];

        let sity_costs = vector[
        vector[0, 240000, 0, 1280000, 0, 5120000, 0],         // SITY costs for Residential Office / House
        vector[80000, 0, 640000, 0, 2560000, 0, 10240000],       // SITY costs for Factory / Entertainment Complex
        vector[0, 240000, 0, 1280000, 0, 5120000, 0],         // SITY costs for House (same as Residential Office)
        vector[80000, 0, 64000, 0, 2560000, 0, 10240000]       // SITY costs for Entertainment Complex (same as Factory)

        ];

        let factory_bonuses = vector[30,55,80,105,130,150,170,200];
        let minted_users = table::new(ctx);  // Initialize the table

        // Initialize GameData with default values
        let game_data = GameData {
            id: object::new(ctx),         
            version:VERSION,             // Initialize a new UID for this game data
            minted: 0,  
            speed: 1, //50x
            cost_multiplier:1 , //0.01x                              
            base_name: string::utf8(b"SuiCity Test v1.3"),   // Default base name for NFTs
            base_url: string::utf8(b"https://suicityp2e.com"), // Default base URL
            base_image_url: string::utf8(b"https://bafybeifbd7bkfgj2urg43i2qwkbsc6pmh3v6cllifxw6z2xiqzfgkryhd4.ipfs.w3s.link/"), // Default image URL
            description: string::utf8(b"FreeMint your SuiCity and start building & earning your $SITY 🏙️ The first onchain Play2Airdrop game which powered by dNFTs"), // Default description
            balance: balance::zero(),                  // Initialize balance to zero
            pool: balance::zero(),                  // Initialize balance to zero
            publisher: publisher_address,    
            accumulation_speeds    ,
            sui_costs: sui_costs,     // SUI costs for each building level
            sity_costs: sity_costs, 
            factory_bonuses: factory_bonuses,
            minted_users: minted_users,  // Initialize the table              
            public_key : x"5A567940437464FF7E491ACB6DC17595ADA001A1241FC34A3620F9DF2382D2E2",
            ref_reward: 500000,
        };

        // Share the GameData object so it can be used by the publisher
        transfer::share_object(game_data);


        let keys = vector[
            b"name".to_string(),
            b"image_url".to_string(),
            b"description".to_string(),
            b"project_url".to_string(),
            b"creator".to_string(),
        ];

        let values = vector[
            // For `name` we can use the `Hero.name` property
            b"{name}".to_string(),
            // For `image_url` we use an IPFS template + `img_url` property.
            b"{url}".to_string(),
            // Description is static for all `Hero` objects.
            b"FreeMint your SuiCity and start building & earning your $SITY 🏙️ The first onchain Play2Airdrop game which powered by dNFTs".to_string(),
            // Project URL is usually static
            b"https://suicityp2e.com".to_string(),
            // Creator field can be any
            b"zeedC".to_string()
        ];

        // Claim the `Publisher` for the package!
        let publisher = package::claim(otw, ctx);

        // Get a new `Display` object for the `Hero` type.
        let mut display = display::new_with_fields<City>(
            &publisher, keys, values, ctx
        );

        // Commit first version of `Display` to apply changes.
        display.update_version();

        transfer::public_transfer(publisher, ctx.sender());
        transfer::public_transfer(display, ctx.sender());
        }

        
    public fun create_pool(
        game: &mut GameData,
        treasury_cap: &mut TreasuryCap<SITY>,
        ctx: &mut TxContext
        ) {
        assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher);

        // Mint a large amount of SITY tokens for the game pool (e.g., 1,000,000 SITY tokens)
        let minted_sity = sity::create( treasury_cap, 1000000000000, ctx); // Mint 1,000,000 SITY
        let sity_balance = coin::into_balance(minted_sity); // Convert minted coins into balance
        balance::join(&mut game.pool, sity_balance);

}
   

    public entry fun withdraw_funds(game: &mut GameData, ctx: &mut TxContext) {

        assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher);

        let amount: u64 = balance::value(&game.balance);

        let raised: Coin<SUI> = coin::take(&mut game.balance, amount, ctx);

        transfer::public_transfer(raised, tx_context::sender(ctx));
    
  }

  /// Entry function to modify accumulation speeds or upgrade costs
    public fun modify_game_data(
        game: &mut GameData,
        new_speed: u64,
        new_cost_multiplier: u64,
        new_accumulation_speeds: vector<u64>,
        new_sui_costs: vector<vector<u64>>,
        new_sity_costs: vector<vector<u64>>,
        new_factory_bonuses: vector<u64>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher); // Only the publisher can modify
        game.accumulation_speeds = new_accumulation_speeds;
        game.speed = new_speed;
        game.cost_multiplier = new_cost_multiplier;
        game.sui_costs = new_sui_costs;
        game.sity_costs = new_sity_costs;
        game.factory_bonuses = new_factory_bonuses;
    }

    entry fun migrate(game: &mut GameData, ctx: & TxContext) {
        assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher); // Only the publisher can modify
        assert!(game.version < VERSION, ENotUpgrade);
        game.version = VERSION;
    }


  // === Private Functions ===

    fun calculate_max_accumulation(game: & GameData, nft:  & City): u64 {
        let total_level = nft.buildings[2] + nft.buildings[3];

        // The base accumulation period is 3 hours, plus more time based on the levels
        if (total_level == 0) {
            return (3 * 3600 * 1000) / game.speed // 3 hours in milliseconds
        } else if (total_level <= 7) {  
            return ((3 + total_level) * 3600 * 1000)/game.speed // Adds 1 hour per level
        } ;
            let result = ((10 + 2 * (total_level - 7)) * 3600 * 1000) / game.speed; // Adds 2 hours per level after level 7
            result
        
        }


    fun calculate_factory_bonus(nft: & City, game: & GameData): u64 {
        // The base daily bonus is 100 SITY tokens
        let factory_level = nft.buildings[1];
        let bonus = game.factory_bonuses[factory_level];

        let hunnid = balance::value(&nft.balance) * bonus;
        hunnid / 100
        }
    
    fun u64_to_string(mut num: u64): string::String {
        let mut result = vector::empty<u8>();

        if (num == 0) {
            vector::push_back(&mut result, 48); // ASCII value for '0'
        } else {
            while (num > 0) {
                let digit = (num % 10) as u8 + 48; // 48 is the ASCII value for '0'
                vector::push_back(&mut result, digit);
                num = num / 10;
            };
            vector::reverse(&mut result);
        };
        
        string::utf8(result)
        }


    fun generate_image_url(
        base_image_url: &string::String,
        residential_office_level: u64,
        factory_level: u64,
        house_level: u64,
        entertainment_complex_level: u64
        ): string::String {
        // Start with the base image URL
        let mut new_image_url = *base_image_url;

        // Convert each building level to a string
        let res_office_str = u64_to_string(residential_office_level);
        let factory_str = u64_to_string(factory_level);
        let house_str = u64_to_string(house_level);
        let entertainment_str = u64_to_string(entertainment_complex_level);

        // Append the levels in the format {residential_office}{factory}{house}{entertainment_complex}
        string::append(&mut new_image_url, res_office_str);
        string::append(&mut new_image_url, factory_str);
        string::append(&mut new_image_url, house_str);
        string::append(&mut new_image_url, entertainment_str);

        // Add the ".png" extension
        let mut png_extension = vector::empty<u8>();
        vector::push_back(&mut png_extension, 46); // ASCII for '.'
        vector::push_back(&mut png_extension, 119); // 'w'
        vector::push_back(&mut png_extension, 101); // 'e'
        vector::push_back(&mut png_extension, 98);  // 'b'
        vector::push_back(&mut png_extension, 112); // 'p'

        string::append(&mut new_image_url, string::utf8(png_extension));

        new_image_url
        }
    
}
module suicity::sity { 
    use sui::coin::{Self,Coin, TreasuryCap};
    use sui::url::{Self};

    public struct SITY has drop {}

    fun init(witness: SITY, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(witness, 3, b"SITY TEST v1.3", b"SITY TEST v1.3", b"BUIDL YOUR SITY", option::some(url::new_unsafe_from_bytes(b"https://bafybeig4236djyafwvxzkb3km7o3xa25lsfg55bxvyrwbxyemlzjnjjpsi.ipfs.w3s.link/sity%20logo.png")), ctx);
        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury, ctx.sender())
    }

    public fun mint(
        treasury_cap: &mut TreasuryCap<SITY>, 
        amount: u64, 
        recipient: address, 
        ctx: &mut TxContext,
    ) {
        let coin = coin::mint(treasury_cap, amount, ctx);
        transfer::public_transfer(coin, recipient)
    }

    public fun create(
        treasury_cap: &mut TreasuryCap<SITY>, 
        amount: u64, 
        ctx: &mut TxContext,
    ): Coin<SITY> {
        let coin = coin::mint(treasury_cap, amount, ctx);
        coin
    }


}
