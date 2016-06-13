/*
biome.cpp
Copyright (C) 2010-2013 kwolekr, Ryan Kwolek <kwolekr@minetest.net>
*/

/*
This file is part of Freeminer.

Freeminer is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Freeminer  is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Freeminer.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "mg_biome.h"
#include "mg_decoration.h"
#include "emerge.h"
#include "gamedef.h"
#include "nodedef.h"
#include "map.h" //for MMVManip
#include "log_types.h"
#include "util/numeric.h"
#include "util/mathconstants.h"
#include "porting.h"
#include "settings.h"


///////////////////////////////////////////////////////////////////////////////


BiomeManager::BiomeManager(IGameDef *gamedef) :
	ObjDefManager(gamedef, OBJDEF_BIOME)
{
	m_gamedef = gamedef;

	// Create default biome to be used in case none exist
	Biome *b = new Biome;

	b->name            = "Default";
	b->flags           = 0;
	b->depth_top       = 0;
	b->depth_filler    = -MAX_MAP_GENERATION_LIMIT;
	b->depth_water_top = 0;
	b->y_min           = -MAX_MAP_GENERATION_LIMIT;
	b->y_max           = MAX_MAP_GENERATION_LIMIT;
	b->heat_point      = 0.0;
	b->humidity_point  = 0.0;

	b->m_nodenames.push_back("mapgen_stone");
	b->m_nodenames.push_back("mapgen_stone");
	b->m_nodenames.push_back("mapgen_stone");
	b->m_nodenames.push_back("mapgen_water_source");
	b->m_nodenames.push_back("mapgen_water_source");
	b->m_nodenames.push_back("mapgen_river_water_source");

	//freeminer
	b->m_nodenames.push_back("mapgen_ice");
	b->m_nodenames.push_back("mapgen_dirt_with_snow");

	b->m_nodenames.push_back("ignore");
	m_ndef->pendNodeResolve(b);

	year_days = g_settings->getS16("year_days");
	weather_heat_season = g_settings->getS16("weather_heat_season");
	weather_heat_daily = g_settings->getS16("weather_heat_daily");
	weather_heat_width = g_settings->getS16("weather_heat_width");
	weather_heat_height = g_settings->getS16("weather_heat_height");
	weather_humidity_season = g_settings->getS16("weather_humidity_season");
	weather_humidity_daily = g_settings->getS16("weather_humidity_daily");
	weather_humidity_width = g_settings->getS16("weather_humidity_width");
	weather_humidity_days = g_settings->getS16("weather_humidity_days");
	weather_hot_core = g_settings->getS16("weather_hot_core");

	if (add(b) == OBJDEF_INVALID_HANDLE)
		delete b;
}


BiomeManager::~BiomeManager()
{
}


void BiomeManager::clear()
{
	EmergeManager *emerge = m_gamedef->getEmergeManager();

	// Remove all dangling references in Decorations
	DecorationManager *decomgr = emerge->decomgr;
	for (size_t i = 0; i != decomgr->getNumObjects(); i++) {
		Decoration *deco = (Decoration *)decomgr->getRaw(i);
		deco->biomes.clear();
	}

	// Don't delete the first biome
	for (size_t i = 1; i < m_objects.size(); i++)
		delete (Biome *)m_objects[i];

	m_objects.clear();
}

////////////////////////////////////////////////////////////////////////////////


void BiomeParamsOriginal::readParams(Settings *settings)
{
	settings->getNoiseParams("mg_biome_np_heat",           np_heat);
	settings->getNoiseParams("mg_biome_np_heat_blend",     np_heat_blend);
	settings->getNoiseParams("mg_biome_np_humidity",       np_humidity);
	settings->getNoiseParams("mg_biome_np_humidity_blend", np_humidity_blend);
}


void BiomeParamsOriginal::writeParams(Settings *settings) const
{
	settings->setNoiseParams("mg_biome_np_heat",           np_heat);
	settings->setNoiseParams("mg_biome_np_heat_blend",     np_heat_blend);
	settings->setNoiseParams("mg_biome_np_humidity",       np_humidity);
	settings->setNoiseParams("mg_biome_np_humidity_blend", np_humidity_blend);
}


////////////////////////////////////////////////////////////////////////////////

BiomeGenOriginal::BiomeGenOriginal(BiomeManager *biomemgr,
	BiomeParamsOriginal *params, v3s16 chunksize)
{
	m_bmgr   = biomemgr;
	m_params = params;
	m_csize  = chunksize;

	noise_heat           = new Noise(&params->np_heat,
									params->seed, m_csize.X, m_csize.Z);
	noise_humidity       = new Noise(&params->np_humidity,
									params->seed, m_csize.X, m_csize.Z);
	noise_heat_blend     = new Noise(&params->np_heat_blend,
									params->seed, m_csize.X, m_csize.Z);
	noise_humidity_blend = new Noise(&params->np_humidity_blend,
									params->seed, m_csize.X, m_csize.Z);

	heatmap  = noise_heat->result;
	humidmap = noise_humidity->result;
	biomemap = new biome_t[m_csize.X * m_csize.Z];
}

BiomeGenOriginal::~BiomeGenOriginal()
{
	delete []biomemap;

	delete noise_heat;
	delete noise_humidity;
	delete noise_heat_blend;
	delete noise_humidity_blend;
}


Biome *BiomeGenOriginal::calcBiomeAtPoint(v3s16 pos) const
{
	float heat =
		NoisePerlin2D(&m_params->np_heat,       pos.X, pos.Z, m_params->seed) +
		NoisePerlin2D(&m_params->np_heat_blend, pos.X, pos.Z, m_params->seed);
	float humidity =
		NoisePerlin2D(&m_params->np_humidity,       pos.X, pos.Z, m_params->seed) +
		NoisePerlin2D(&m_params->np_humidity_blend, pos.X, pos.Z, m_params->seed);

	return calcBiomeFromNoise(heat, humidity, pos.Y);
}


void BiomeGenOriginal::calcBiomeNoise(v3s16 pmin)
{
	m_pmin = pmin;

	noise_heat->perlinMap2D(pmin.X, pmin.Z);
	noise_humidity->perlinMap2D(pmin.X, pmin.Z);
	noise_heat_blend->perlinMap2D(pmin.X, pmin.Z);
	noise_humidity_blend->perlinMap2D(pmin.X, pmin.Z);

	for (s32 i = 0; i < m_csize.X * m_csize.Z; i++) {
		noise_heat->result[i]     += noise_heat_blend->result[i];
		noise_humidity->result[i] += noise_humidity_blend->result[i];
	}
}


biome_t *BiomeGenOriginal::getBiomes(s16 *heightmap)
{
	for (s32 i = 0; i != m_csize.X * m_csize.Z; i++) {
		Biome *biome = calcBiomeFromNoise(
			noise_heat->result[i],
			noise_humidity->result[i],
			heightmap[i]);

		biomemap[i] = biome->index;
	}

	return biomemap;
}


Biome *BiomeGenOriginal::getBiomeAtPoint(v3s16 pos) const
{
	return getBiomeAtIndex(
		(pos.Z - m_pmin.Z) * m_csize.X + (pos.X - m_pmin.X),
		pos.Y);
}


Biome *BiomeGenOriginal::getBiomeAtIndex(size_t index, s16 y) const
{
	return calcBiomeFromNoise(
		noise_heat->result[index],
		noise_humidity->result[index],
		y);
}


Biome *BiomeGenOriginal::calcBiomeFromNoise(float heat, float humidity, s16 y) const
{
	Biome *b, *biome_closest = NULL;
	float dist_min = FLT_MAX;

	for (size_t i = 1; i < m_bmgr->getNumObjects(); i++) {
		b = (Biome *)m_bmgr->getRaw(i);
		if (!b || y > b->y_max || y < b->y_min)
			continue;
		float heat_point = (b->heat_point - 50) * (( m_params->np_heat.offset + m_params->np_heat.scale ) / 100)
			 + m_params->np_heat.offset;

		float d_heat     = heat     - heat_point;

		float d_humidity = humidity - b->humidity_point;
		float dist = (d_heat * d_heat) +
					 (d_humidity * d_humidity);
		if (dist < dist_min) {
			dist_min = dist;
			biome_closest = b;
		}
	}

	return biome_closest ? biome_closest : (Biome *)m_bmgr->getRaw(BIOME_NONE);
}

// Freeminer Weather
s16 BiomeManager::calcBlockHeat(v3POS p, uint64_t seed, float timeofday, float totaltime, bool use_weather) {
	//variant 1: full random
	//f32 heat = NoisePerlin3D(np_heat, p.X, env->getGameTime()/100, p.Z, seed);

	//variant 2: season change based on default heat map
	auto heat = NoisePerlin2D(&(mapgen_params->bparams->np_heat), p.X, p.Z, seed); // -30..20..70

	if (use_weather) {
		f32 seasonv = totaltime;
		seasonv /= 86400 * year_days; // season change speed
		seasonv += (f32)p.X / weather_heat_width; // you can walk to area with other season
		seasonv = sin(seasonv * M_PI);
		//heat += (weather_heat_season * (heat < offset ? 2 : 0.5)) * seasonv; // -60..0..30
		heat += (weather_heat_season) * seasonv; // -60..0..30

		// daily change, hotter at sun +4, colder at night -4
		heat += weather_heat_daily * (sin(cycle_shift(timeofday, -0.25) * M_PI) - 0.5); //-64..0..34
	}
	heat += p.Y / weather_heat_height; // upper=colder, lower=hotter, 3c per 1000

	if (weather_hot_core && p.Y < -(MAX_MAP_GENERATION_LIMIT-weather_hot_core))
		heat += 6000 * (1.0-((float)(p.Y - -MAX_MAP_GENERATION_LIMIT)/weather_hot_core)); //hot core, later via realms

	return heat;
}


s16 BiomeManager::calcBlockHumidity(v3POS p, uint64_t seed, float timeofday, float totaltime, bool use_weather) {

	auto humidity = NoisePerlin2D(&(mapgen_params->bparams->np_humidity), p.X, p.Z, seed);
	humidity *= 1.0 - ((float)p.Y / MAX_MAP_GENERATION_LIMIT);

	if (use_weather) {
		f32 seasonv = totaltime;
		seasonv /= 86400 * weather_humidity_days; // bad weather change speed (2 days)
		seasonv += (f32)p.Z / weather_humidity_width;
		humidity += weather_humidity_season * sin(seasonv * M_PI);
		humidity += weather_humidity_daily * (sin(cycle_shift(timeofday, -0.1) * M_PI) - 0.5);
	}

	humidity = rangelim(humidity, 0, 100);

	return humidity;
}
//===============fm end


////////////////////////////////////////////////////////////////////////////////

void Biome::resolveNodeNames()
{
	getIdFromNrBacklog(&c_top,         "mapgen_stone",              CONTENT_AIR);
	getIdFromNrBacklog(&c_filler,      "mapgen_stone",              CONTENT_AIR);
	getIdFromNrBacklog(&c_stone,       "mapgen_stone",              CONTENT_AIR);
	getIdFromNrBacklog(&c_water_top,   "mapgen_water_source",       CONTENT_AIR);
	getIdFromNrBacklog(&c_water,       "mapgen_water_source",       CONTENT_AIR);
	getIdFromNrBacklog(&c_river_water, "mapgen_river_water_source", CONTENT_AIR);

	//freeminer:
	getIdFromNrBacklog(&c_ice,         "mapgen_ice",                c_water);
	getIdFromNrBacklog(&c_top_cold,    "mapgen_dirt_with_snow",     c_top);

	getIdFromNrBacklog(&c_dust,        "ignore",                    CONTENT_IGNORE);
}
