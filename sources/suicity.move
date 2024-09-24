
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
    const EInvalidSignature: u64 = 5;
    const EInvalidTokenType: u64 = 6;
    const EZeroBalance : u64 = 7;
    const ENotEnoughTime : u64 = 8;
    const ENotEligibleForRef : u64 = 9;
    const ERefAlreadyUsed : u64 = 10;
    const EInsufficientPool : u64 = 11;
    const EAmountShouldBePositive : u64 = 12;

  // === Constants ===
    const VERSION: u64 = 1;

  // === Structs ===
    public struct NFT has drop {}

    public struct City has key  {
        id: UID,

        index: u64,
        name: string::String,
        description: string::String,
        url: Url,
        balance: Balance<SITY>,
        buildings: vector<u64>,  
        last_claimed: u64,
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
        cost_multiplier: u64,                      
        base_name: string::String,    
        base_url: string::String,    
        base_image_url: string::String, 
        description: string::String,  
        balance: Balance<SUI>,   
        pool: Balance<SITY>,   
        publisher: address,      
        accumulation_speeds: vector<u64>,   
        building_sui_costs: vector<vector<u64>>,     
        building_sity_costs: vector<vector<u64>>,  
        factory_bonuses: vector<u64>,
        minted_users: Table<address, MintedByUser>,  
        public_key: vector<u8>, 
        ref_reward: u64,

        extra_sui_costs: vector<u64>, 
        extra_sity_costs: vector<u64>, 
        

    }
    // ===== Events =====

    public struct MintedByUser has store, drop {
    user_minted: bool,  
    }
    public struct SITYClaimed has copy, drop {
        
        nft_id: ID,
        amount: u64,
        claimer: address,
        }

    public struct NFTMinted has copy, drop {
        object_id: ID,
        creator: address,
        name: string::String,
        }

    public struct BonusClaimed has copy, drop {
        object_id: ID,
        amount: u64,
        }

        public struct RewardClaimed has copy, drop {
        claimer: address,
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

        accumulate_sity(nft, game, clock, ctx);

        let sender = tx_context::sender(ctx);

        let sity_balance = balance::value(&nft.balance);

        assert!(sity_balance > 0, EZeroBalance);

        let claimed_sity = coin::take(&mut nft.balance, sity_balance, ctx);

        transfer::public_transfer(claimed_sity, sender);

            event::emit(SITYClaimed {
            nft_id: object::uid_to_inner(&nft.id),
            amount: sity_balance,
            claimer: sender,
        });
        let current_time = sui::clock::timestamp_ms(clock);

        nft.last_claimed = current_time;

        }

    public entry fun claim_factory_bonus(nft: &mut City, game: &mut GameData, clock: &sui::clock::Clock, ctx: &mut TxContext) {

        accumulate_sity(nft, game, clock, ctx);
        let current_time = sui::clock::timestamp_ms(clock);

        let time_since_last_claim = current_time - nft.last_daily_bonus;
        assert!(time_since_last_claim >= (24 * 3600 * 1000) / game.speed, ENotEnoughTime); // 24 hours

        let daily_bonus = calculate_factory_bonus( nft,game);
        let reward = coin::take(&mut game.pool, daily_bonus, ctx);

        nft.last_daily_bonus = current_time;

        transfer::public_transfer(reward, tx_context::sender(ctx));

        event::emit(BonusClaimed{
            object_id:object::id(nft),
            amount:daily_bonus
        });
        }

  public entry fun claim_reward(
      game: &mut GameData,
       sig: vector<u8>,         
       msg: vector<u8>,      
      amount: u64,              
      ctx: &mut TxContext       
  ) {
      let is_valid_signature = ed25519::ed25519_verify(&sig, &game.public_key, &msg);
      assert!(is_valid_signature, EInvalidSignature); 


      assert!(amount > 0, EAmountShouldBePositive); 

      let pool_balance = balance::value(&game.pool);
      assert!(pool_balance >= amount, EInsufficientPool);

      let claimed_sity = coin::take(&mut game.pool, amount, ctx);

      let claimer = tx_context::sender(ctx);
      transfer::public_transfer(claimed_sity, claimer);

      event::emit(RewardClaimed {
          claimer: claimer,
          amount: amount,
      });
  }

  public entry fun claim_reference(
      game: &mut GameData,
      nft: &mut City,
      ref_owner: address,
       sig: vector<u8>,          
       msg: vector<u8>,     
      ctx: &mut TxContext       
  ) {

    

      let total_building_level = nft.buildings[0] + nft.buildings[1] + nft.buildings[2] + nft.buildings[3];

      assert!(total_building_level >= 3, ENotEligibleForRef); 
      
      assert!(nft.ref_used == false, ERefAlreadyUsed); 
      
      let is_valid_signature = ed25519::ed25519_verify(&sig, &game.public_key, &msg);
      assert!(is_valid_signature, EInvalidSignature); 

      let amount = game.ref_reward;

      let pool_balance = balance::value(&game.pool);
      assert!(pool_balance >= (2*amount), EInsufficientPool); 

      let claimed_sity = coin::take(&mut game.pool, amount, ctx);

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
        assert!(game.version == VERSION, EWrongVersion); 

        let sender = ctx.sender();

        if (table::contains(&game.minted_users, sender)) {
            assert!(false, EAlreadyMinted);  
        };

        let mut nft_name = game.base_name;
        string::append(&mut nft_name, string::utf8(vector::singleton(32))); 
        string::append(&mut nft_name, string::utf8(vector::singleton(35))); 
        let mint_number_str = u64_to_string(game.minted + 1);
        string::append(&mut nft_name, mint_number_str);

        let mut image_url = game.base_image_url;
        string::append(&mut image_url, string::utf8(vector::singleton(48))); 
        string::append(&mut image_url, string::utf8(vector::singleton(48))); 
        string::append(&mut image_url, string::utf8(vector::singleton(48))); 
        let mut png_extension = vector::empty<u8>();
        vector::push_back(&mut png_extension, 46); 
        vector::push_back(&mut png_extension, 119);
        vector::push_back(&mut png_extension, 101); 
        vector::push_back(&mut png_extension, 98);  
        vector::push_back(&mut png_extension, 112); 

        string::append(&mut image_url, string::utf8(png_extension));



        let minted_user = MintedByUser { user_minted: true };
        table::add(&mut game.minted_users, sender, minted_user);


    let nft = City {
        id: object::new(ctx),
        index: game.minted + 1,
        name: nft_name,
        description: game.description, 
        url: url::new_unsafe_from_bytes(string::into_bytes(image_url)),
        balance: balance::zero(),
        buildings: vector[0,0,0,0,0,0,0,0],  

        last_claimed: sui::clock::timestamp_ms(clock),
        last_daily_bonus: sui::clock::timestamp_ms(clock) - (24 * 3600 * 1000), 
        last_accumulated: sui::clock::timestamp_ms(clock),
        population: 40000,
        ref_used    : false,
        };


    event::emit(NFTMinted {
        object_id: object::id(&nft),
        creator: sender,
        name: nft.name,
        });

        
        transfer::transfer(nft, sender);
        game.minted = game.minted + 1;
        }

        public fun calculate_population(nft: &City): u64 {

        let mut population_res = 10000;
        let mut i = 0;
        while (i < nft.buildings[0]) {
            population_res = population_res * 14 / 10; 
            i = i + 1;
        };

        let mut population_house = 10000;
        let mut j = 0;
        while (j < nft.buildings[1]) {
            population_house = population_house * 14 / 10; 
            j = j + 1;
        };

        let mut population_factory = 10000;
        let mut k = 0;
        while (k < nft.buildings[2]) {
            population_factory = population_factory * 14 / 10; 
            k = k + 1;
        };

        let mut population_entertainment = 10000;
        let mut l = 0;
        while (l < nft.buildings[3]) {
            population_entertainment = population_entertainment * 14 / 10; 
            l = l + 1;
        };



        population_res + population_house + population_factory + population_entertainment + nft.balance.value()
        }

    public fun upgrade_building_with_sui(
        nft: &mut City,
        game: &mut GameData,
        building_type: u8, 
        sui: Coin<SUI>,    
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
        ) {
        accumulate_sity(nft, game, clock, ctx);

        let current_level = nft.buildings[building_type as u64];  

        let index = building_type as u64;
        let sui_cost = game.building_sui_costs[index][current_level] * game.cost_multiplier;
        let adjusted_sui_cost = sui_cost / 100;
        assert!(sui_cost!=0, EInvalidTokenType);

        let sui_value = coin::value(&sui);
        assert!(sui_value >= adjusted_sui_cost, EInsufficientBalance); 


        balance::join(&mut game.balance, coin::into_balance(sui));

        let building_ref = vector::borrow_mut(&mut nft.buildings, building_type as u64);
        *building_ref = current_level + 1;

        let new_population = calculate_population(nft);
        nft.population = new_population;

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

        public fun upgrade_building_with_sity(
        nft: &mut City,
        game: &mut GameData,
        building_type: u8, 
        sity: Coin<SITY>,  
        clock: &sui::clock::Clock,
        ctx: &mut TxContext
        ) {
        accumulate_sity(nft, game, clock, ctx);

        let current_level = nft.buildings[building_type as u64];  


        let index = building_type as u64;


        let sity_cost = game.building_sity_costs[index][current_level]* game.cost_multiplier;
        assert!(sity_cost!=0,EInvalidTokenType);

        let adjusted_sity_cost = sity_cost / 100;

        let sity_value = coin::value(&sity);
        assert!(sity_value >= adjusted_sity_cost, EInsufficientBalance); // Ensure the correct SITY amount is passed

        balance::join(&mut game.pool, coin::into_balance(sity));

        let building_ref = vector::borrow_mut(&mut nft.buildings, building_type as u64);
        *building_ref = current_level + 1;

        let new_population = calculate_population(nft);
        nft.population = new_population;

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
 public entry fun change_name_with_sui(nft: &mut City,
        game: &mut GameData,sui: Coin<SUI>, 
        new_name : string::String,
        _ctx: &mut TxContext){

        let sui_cost = game.extra_sui_costs[0] * game.cost_multiplier;
        let adjusted_sui_cost = sui_cost / 100;
        assert!(sui_cost!=0, EInvalidTokenType);

        let sui_value = coin::value(&sui);
        assert!(sui_value >= adjusted_sui_cost, EInsufficientBalance); 

        balance::join(&mut game.balance, coin::into_balance(sui));

        nft.name = new_name;

        }


         public entry fun change_name_with_sity(nft: &mut City,
        game: &mut GameData,sui: Coin<SUI>, 
        sig: vector<u8>,          
        msg: vector<u8>,      
        _ctx: &mut TxContext){

        let is_valid_signature = ed25519::ed25519_verify(&sig, &game.public_key, &msg);
        assert!(is_valid_signature, EInvalidSignature); 

        let sui_cost = game.extra_sity_costs[0] * game.cost_multiplier;
        let adjusted_sui_cost = sui_cost / 100; 
        assert!(sui_cost!=0, EInvalidTokenType);

        let sui_value = coin::value(&sui);
        assert!(sui_value >= adjusted_sui_cost, EInsufficientBalance); 

        balance::join(&mut game.balance, coin::into_balance(sui));

        nft.name = msg.to_string();

        }
   


    public entry fun burn(nft: City, _: &mut TxContext) {
        let City { id, index:_, name: _, description: _, url: _, balance:bal,buildings: _, last_claimed: _, last_daily_bonus:_, last_accumulated: _, population : _, ref_used: _} = nft;
        balance::destroy_zero(bal);
        id.delete()
        }


    // ===== Public view functions =====

    public fun name(nft: &City): &string::String {
        &nft.name
        }

    public fun description(nft: &City): &string::String {
        &nft.description
        }

    public fun url(nft: &City): &Url {
        &nft.url
        }
    

  // === Admin Functions ===

    fun init(otw: NFT, ctx: &mut TxContext) {
        let publisher_address = tx_context::sender(ctx);

        let accumulation_speeds = vector[100000, 180000, 310000, 550000, 960000, 1700000, 3000000, 5125000];

        let building_sui_costs = vector[
        vector[800000000, 0, 4000000000, 0, 20000000000, 0, 75000000000],         
        vector[0, 0, 0, 9500000000, 0, 35000000000, 0], 
        vector[800000000, 0, 4000000000, 0, 20000000000, 0, 75000000000],         
        vector[0, 1800000000, 0, 9500000000, 0, 35000000000, 0] 
        ];

        let building_sity_costs = vector[
        vector[0, 620000, 0, 2900000, 0, 9400000, 0],         
        vector[200000, 620000, 1400000, 0, 6200000, 0, 20000000],       
        vector[0, 620000, 0, 2900000, 0, 9400000, 0],         
        vector[200000, 0, 1400000, 0, 6200000, 0, 20000000]       

        ];

        let extra_sity_costs = vector[1000000];
        let extra_sui_costs = vector[10000000000];

        let factory_bonuses = vector[30,55,80,105,130,150,170,200];
        let minted_users = table::new(ctx); 

        let game_data = GameData {
            id: object::new(ctx),         
            version:VERSION,             
            minted: 0,  
            speed: 1, 
            cost_multiplier:1 ,                            
            base_name: string::utf8(b"SuiCity"),  
            base_url: string::utf8(b"https://suicityp2e.com"), 
            base_image_url: string::utf8(b"https://bafybeifbd7bkfgj2urg43i2qwkbsc6pmh3v6cllifxw6z2xiqzfgkryhd4.ipfs.w3s.link/"), 
            description: string::utf8(b"FreeMint your SuiCity and start building & earning your $SITY 🏙️ The first onchain Play2Airdrop game which powered by dNFTs"), 
            balance: balance::zero(),                  
            pool: balance::zero(),                  
            publisher: publisher_address,    
            accumulation_speeds    ,
            building_sui_costs: building_sui_costs,     
            building_sity_costs: building_sity_costs, 
            extra_sui_costs: extra_sui_costs,
            extra_sity_costs: extra_sity_costs,
            factory_bonuses: factory_bonuses,
            minted_users: minted_users,               
            public_key : x"5A567940437464FF7E491ACB6DC17595ADA001A1241FC34A3620F9DF2382D2E2",
            ref_reward: 500000,
        };

        transfer::share_object(game_data);


        let keys = vector[
            b"name".to_string(),
            b"image_url".to_string(),
            b"description".to_string(),
            b"project_url".to_string(),
            b"creator".to_string(),
        ];

        let values = vector[
            b"{name}".to_string(),
            b"{url}".to_string(),
            b"FreeMint your SuiCity and start building & earning your $SITY 🏙️ The first onchain Play2Airdrop game which powered by dNFTs".to_string(),
            b"https://suicityp2e.com".to_string(),
            b"zeedC".to_string()
        ];

        let publisher = package::claim(otw, ctx);

        let mut display = display::new_with_fields<City>(
            &publisher, keys, values, ctx
        );

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

        let minted_sity = sity::create( treasury_cap, 10000000000, ctx); 
        let sity_balance = coin::into_balance(minted_sity); 
        balance::join(&mut game.pool, sity_balance);

}
   

    public entry fun withdraw_funds(game: &mut GameData, ctx: &mut TxContext) {

        assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher);

        let amount: u64 = balance::value(&game.balance);

        let raised: Coin<SUI> = coin::take(&mut game.balance, amount, ctx);

        transfer::public_transfer(raised, tx_context::sender(ctx));
    
  }

    public fun modify_game_data(
        game: &mut GameData,
        new_speed: u64,
        new_cost_multiplier: u64,
        new_accumulation_speeds: vector<u64>,
        new_building_sui_costs: vector<vector<u64>>,
        new_building_sity_costs: vector<vector<u64>>,
        new_factory_bonuses: vector<u64>,
        new_ref_reward: u64,
        new_extra_sui_costs: vector<u64>,
        new_extra_sity_costs: vector<u64>,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher);
        game.accumulation_speeds = new_accumulation_speeds;
        game.speed = new_speed;
        game.cost_multiplier = new_cost_multiplier;
        game.building_sui_costs = new_building_sui_costs;
        game.building_sity_costs = new_building_sity_costs;
        game.factory_bonuses = new_factory_bonuses;
        game.ref_reward = new_ref_reward;
        game.extra_sui_costs = new_extra_sui_costs;
        game.extra_sity_costs = new_extra_sity_costs;
    }

    entry fun migrate(game: &mut GameData, ctx: & TxContext) {
        assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher); 
        assert!(game.version < VERSION, ENotUpgrade);
        game.version = VERSION;
    }

    public fun modify_cost_multiplier(
                game: &mut GameData,
            new_cost_multiplier: u64,
            ctx: &mut TxContext

    ){
                assert!(tx_context::sender(ctx) == game.publisher, ENotPublisher); 
                game.cost_multiplier = new_cost_multiplier;

    }


  // === Private Functions ===

    fun calculate_max_accumulation(game: & GameData, nft:  & City): u64 {
        let total_level = nft.buildings[2] + nft.buildings[3];

        if (total_level == 0) {
            return (3 * 3600 * 1000) / game.speed 
        } else if (total_level <= 7) {  
            return ((3 + total_level) * 3600 * 1000)/game.speed 
        } ;
            let result = ((10 + 2 * (total_level - 7)) * 3600 * 1000) / game.speed; 
            result
        
        }


    fun calculate_factory_bonus(nft: & City, game: & GameData): u64 {
        let factory_level = nft.buildings[1];
        let bonus = game.factory_bonuses[factory_level];

        let hunnid = balance::value(&nft.balance) * bonus;
        hunnid / 100
        }
    
    fun u64_to_string(mut num: u64): string::String {
        let mut result = vector::empty<u8>();

        if (num == 0) {
            vector::push_back(&mut result, 48); 
        } else {
            while (num > 0) {
                let digit = (num % 10) as u8 + 48; 
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
        let mut new_image_url = *base_image_url;

        let res_office_str = u64_to_string(residential_office_level);
        let factory_str = u64_to_string(factory_level);
        let house_str = u64_to_string(house_level);
        let entertainment_str = u64_to_string(entertainment_complex_level);

        // Append the levels in the format {residential_office}{factory}{house}{entertainment_complex}
        string::append(&mut new_image_url, res_office_str);
        string::append(&mut new_image_url, factory_str);
        string::append(&mut new_image_url, house_str);
        string::append(&mut new_image_url, entertainment_str);

        let mut png_extension = vector::empty<u8>();
        vector::push_back(&mut png_extension, 46); 
        vector::push_back(&mut png_extension, 119); 
        vector::push_back(&mut png_extension, 101); 
        vector::push_back(&mut png_extension, 98);  
        vector::push_back(&mut png_extension, 112); 

        string::append(&mut new_image_url, string::utf8(png_extension));

        new_image_url
        }
    
}
module suicity::sity { 
    use sui::coin::{Self,Coin, TreasuryCap};
    use sui::url::{Self};

    public struct SITY has drop {}

    fun init(witness: SITY, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(witness, 3, b"SITY", b"SITY", b"Native token of @SuiCityP2E", option::some(url::new_unsafe_from_bytes(b"https://bafybeig4236djyafwvxzkb3km7o3xa25lsfg55bxvyrwbxyemlzjnjjpsi.ipfs.w3s.link/sity%20logo.png")), ctx);
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
